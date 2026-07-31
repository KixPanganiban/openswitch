import Darwin
import Foundation

/// A plugin directory that passed manifest and script validation.
final class LoadedPlugin: NSObject {
    let dirName: String
    let directoryURL: URL
    let title: String
    let icon: String?
    let children: [PluginChild]?
    let onClickURL: URL?

    init(
        dirName: String,
        directoryURL: URL,
        title: String,
        icon: String?,
        children: [PluginChild]?,
        onClickURL: URL?
    ) {
        self.dirName = dirName
        self.directoryURL = directoryURL
        self.title = title
        self.icon = icon
        self.children = children
        self.onClickURL = onClickURL
    }
}

/// One child row in a plugin submenu.
struct PluginChild {
    let onRenderURL: URL
    let onClickURL: URL?
}

/// Click target stored on a child menu item.
final class PluginClickTarget: NSObject {
    let plugin: LoadedPlugin
    let childIndex: Int

    init(plugin: LoadedPlugin, childIndex: Int) {
        self.plugin = plugin
        self.childIndex = childIndex
    }
}

/// A discovered plugin directory — valid manifest or a load error.
enum PluginEntry {
    case valid(LoadedPlugin)
    case invalid(dirName: String, reason: String)
}

/// Discovers plugins once, validates manifests, and runs onRender/onClick scripts.
final class PluginManager {
    private static let pluginsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/openswitch/plugins", isDirectory: true)
    private static let renderBudget: TimeInterval = 0.5
    private static let scriptTimeout: TimeInterval = 30
    private static let outputLimit = 80

    private struct PluginManifest: Decodable {
        let title: String?
        let icon: String?
        let onClick: String?
        let children: [ChildManifest]?
    }

    private struct ChildManifest: Decodable {
        let onRender: String?
        let onClick: String?
    }

    private enum ScriptOutcome {
        case success(String)
        case failure(String)
    }

    private struct RenderKey: Hashable {
        let dirName: String
        let childIndex: Int
    }

    let entries: [PluginEntry]

    private var renderCache: [RenderKey: String] = [:]
    private var renderGeneration: [RenderKey: Int] = [:]
    private let stateLock = NSLock()

    init() {
        entries = Self.discoverPlugins()
    }

    func displayTitle(for plugin: LoadedPlugin) -> String {
        if let icon = plugin.icon, !icon.isEmpty {
            return "\(icon) \(plugin.title)"
        }
        return plugin.title
    }

    func cachedTitle(plugin: LoadedPlugin, childIndex: Int) -> String? {
        cachedTitle(dirName: plugin.dirName, childIndex: childIndex)
    }

    /// Runs all child onRender scripts concurrently with a shared 500 ms budget, then
    /// applies titles via `applyTitle` on the main thread (including late updates).
    func refreshChildren(plugin: LoadedPlugin, applyTitle: @escaping (Int, String) -> Void) {
        guard let children = plugin.children, !children.isEmpty else { return }

        let generation = bumpGenerations(plugin: plugin, childCount: children.count)
        let pluginDir = plugin.directoryURL
        let dirName = plugin.dirName

        var outcomes = [Int: ScriptOutcome]()
        let outcomesLock = NSLock()
        let group = DispatchGroup()

        for (index, child) in children.enumerated() {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                let outcome = Self.runScript(at: child.onRenderURL, pluginDir: pluginDir)
                outcomesLock.lock()
                outcomes[index] = outcome
                outcomesLock.unlock()
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            _ = group.wait(timeout: .now() + Self.renderBudget)

            var pendingAfterBudget = Set<Int>()
            for index in children.indices {
                outcomesLock.lock()
                let outcome = outcomes[index]
                outcomesLock.unlock()
                if outcome == nil {
                    pendingAfterBudget.insert(index)
                }
            }

            DispatchQueue.main.async { [self] in
                for index in children.indices {
                    guard self.isCurrentGeneration(dirName: dirName, childIndex: index, generation: generation) else {
                        continue
                    }
                    outcomesLock.lock()
                    let outcome = outcomes[index]
                    outcomesLock.unlock()
                    let title = self.titleForRender(
                        outcome: outcome,
                        dirName: dirName,
                        childIndex: index,
                        generation: generation
                    )
                    applyTitle(index, title)
                }
            }

            group.wait()

            for index in pendingAfterBudget {
                outcomesLock.lock()
                let outcome = outcomes[index]
                outcomesLock.unlock()
                guard let outcome else { continue }

                DispatchQueue.main.async { [self] in
                    guard self.isCurrentGeneration(dirName: dirName, childIndex: index, generation: generation) else {
                        return
                    }
                    let title = self.titleForRender(
                        outcome: outcome,
                        dirName: dirName,
                        childIndex: index,
                        generation: generation
                    )
                    applyTitle(index, title)
                }
            }
        }
    }

    /// Runs a leaf or child onClick script off the main thread. Returns an error message on failure.
    func runOnClick(plugin: LoadedPlugin, childIndex: Int?) -> String? {
        let scriptURL: URL
        if let childIndex {
            guard let children = plugin.children, childIndex >= 0, childIndex < children.count,
                  let url = children[childIndex].onClickURL else {
                return "missing onClick script"
            }
            scriptURL = url
        } else {
            guard let url = plugin.onClickURL else { return "missing onClick script" }
            scriptURL = url
        }

        switch Self.runScript(at: scriptURL, pluginDir: plugin.directoryURL) {
        case .success:
            return nil
        case .failure(let message):
            return message
        }
    }

    private func bumpGenerations(plugin: LoadedPlugin, childCount: Int) -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        let next = (renderGeneration[RenderKey(dirName: plugin.dirName, childIndex: 0)] ?? 0) + 1
        for index in 0..<childCount {
            renderGeneration[RenderKey(dirName: plugin.dirName, childIndex: index)] = next
        }
        return next
    }

    private func isCurrentGeneration(dirName: String, childIndex: Int, generation: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return renderGeneration[RenderKey(dirName: dirName, childIndex: childIndex)] == generation
    }

    private func titleForRender(
        outcome: ScriptOutcome?,
        dirName: String,
        childIndex: Int,
        generation: Int
    ) -> String {
        guard isCurrentGeneration(dirName: dirName, childIndex: childIndex, generation: generation) else {
            return cachedTitle(dirName: dirName, childIndex: childIndex) ?? "…"
        }

        switch outcome {
        case .success(let line):
            storeCache(dirName: dirName, childIndex: childIndex, title: line)
            return line
        case .failure(let message):
            return message
        case nil:
            return cachedTitle(dirName: dirName, childIndex: childIndex) ?? "…"
        }
    }

    private func cachedTitle(dirName: String, childIndex: Int) -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return renderCache[RenderKey(dirName: dirName, childIndex: childIndex)]
    }

    private func storeCache(dirName: String, childIndex: Int, title: String) {
        stateLock.lock()
        renderCache[RenderKey(dirName: dirName, childIndex: childIndex)] = title
        stateLock.unlock()
    }

    private static func discoverPlugins() -> [PluginEntry] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: pluginsRoot.path) else { return [] }

        guard let names = try? fileManager.contentsOfDirectory(atPath: pluginsRoot.path) else { return [] }

        return names.sorted().compactMap { name -> PluginEntry? in
            let dirURL = pluginsRoot.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: dirURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return loadPlugin(dirName: name, directoryURL: dirURL)
        }
    }

    private static func loadPlugin(dirName: String, directoryURL: URL) -> PluginEntry {
        let manifestURL = directoryURL.appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return .invalid(dirName: dirName, reason: "missing plugin.json")
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            return .invalid(dirName: dirName, reason: "cannot read plugin.json")
        }

        let manifest: PluginManifest
        do {
            manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        } catch {
            return .invalid(dirName: dirName, reason: "invalid plugin.json")
        }

        guard let title = manifest.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return .invalid(dirName: dirName, reason: "title is required")
        }

        let icon = manifest.icon

        if let children = manifest.children, !children.isEmpty {
            var parsedChildren: [PluginChild] = []
            for (index, child) in children.enumerated() {
                guard let onRender = child.onRender else {
                    return .invalid(dirName: dirName, reason: "child \(index) missing onRender")
                }
                switch validateExecutable(relativePath: onRender, pluginDir: directoryURL) {
                case .ok(let url):
                    var onClickURL: URL?
                    if let onClick = child.onClick {
                        switch validateExecutable(relativePath: onClick, pluginDir: directoryURL) {
                        case .ok(let clickURL):
                            onClickURL = clickURL
                        case .err(let reason):
                            return .invalid(dirName: dirName, reason: "child \(index) onClick: \(reason)")
                        }
                    }
                    parsedChildren.append(PluginChild(onRenderURL: url, onClickURL: onClickURL))
                case .err(let reason):
                    return .invalid(dirName: dirName, reason: "child \(index) onRender: \(reason)")
                }
            }
            return .valid(LoadedPlugin(
                dirName: dirName,
                directoryURL: directoryURL,
                title: title,
                icon: icon,
                children: parsedChildren,
                onClickURL: nil
            ))
        }

        guard let onClick = manifest.onClick else {
            return .invalid(dirName: dirName, reason: "onClick is required for leaf plugins")
        }
        switch validateExecutable(relativePath: onClick, pluginDir: directoryURL) {
        case .ok(let url):
            return .valid(LoadedPlugin(
                dirName: dirName,
                directoryURL: directoryURL,
                title: title,
                icon: icon,
                children: nil,
                onClickURL: url
            ))
        case .err(let reason):
            return .invalid(dirName: dirName, reason: "onClick: \(reason)")
        }
    }

    private enum ScriptValidation {
        case ok(URL)
        case err(String)
    }

    private static func validateExecutable(relativePath: String, pluginDir: URL) -> ScriptValidation {
        guard !relativePath.isEmpty else { return .err("path is empty") }

        let candidate = pluginDir.appendingPathComponent(relativePath)
        guard let pluginCanonical = canonicalPath(pluginDir) else {
            return .err("cannot resolve plugin directory")
        }
        guard let scriptCanonical = canonicalPath(candidate) else {
            return .err("cannot resolve script path")
        }
        guard scriptCanonical.hasPrefix(pluginCanonical + "/") || scriptCanonical == pluginCanonical else {
            return .err("script escapes plugin directory")
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: scriptCanonical, isDirectory: &isDirectory) else {
            return .err("script is not a regular file")
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: scriptCanonical),
              let fileType = attrs[.type] as? FileAttributeType,
              fileType == .typeRegular else {
            return .err("script is not a regular file")
        }
        guard FileManager.default.isExecutableFile(atPath: scriptCanonical) else {
            return .err("script is not executable")
        }

        return .ok(URL(fileURLWithPath: scriptCanonical, isDirectory: false))
    }

    private static func canonicalPath(_ url: URL) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(url.path, &buffer) != nil else { return nil }
        return String(cString: buffer)
    }

    private static func runScript(at scriptURL: URL, pluginDir: URL) -> ScriptOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            "-e", "setpgrp; exec {$ARGV[0]} @ARGV",
            scriptURL.path,
        ]
        process.currentDirectoryURL = pluginDir

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        var stdoutData = Data()
        var stderrData = Data()
        let dataLock = NSLock()

        stdoutHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            dataLock.lock()
            stdoutData.append(chunk)
            dataLock.unlock()
        }
        stderrHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            dataLock.lock()
            stderrData.append(chunk)
            dataLock.unlock()
        }

        do {
            try process.run()
        } catch {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            return .failure("launch failed")
        }

        let exitGroup = DispatchGroup()
        exitGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            exitGroup.leave()
        }

        let timedOut = exitGroup.wait(timeout: .now() + scriptTimeout) == .timedOut
        if timedOut {
            process.terminate()
            _ = exitGroup.wait(timeout: .now() + 0.5)
            kill(-process.processIdentifier, SIGKILL)
            exitGroup.wait()
            pollDrainPipeHandles(
                stdout: stdoutHandle,
                stderr: stderrHandle,
                stdoutData: &stdoutData,
                stderrData: &stderrData,
                lock: dataLock
            )
            return .failure("timeout")
        }

        exitGroup.wait()
        pollDrainPipeHandles(
            stdout: stdoutHandle,
            stderr: stderrHandle,
            stdoutData: &stdoutData,
            stderrData: &stderrData,
            lock: dataLock
        )

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return .success(formatOutput(stdout))
        }

        let errorText = formatOutput(stderr.isEmpty ? stdout : stderr)
        if errorText.isEmpty {
            return .failure("exit \(process.terminationStatus)")
        }
        return .failure(errorText)
    }

    private static func pollDrainPipeHandles(
        stdout: FileHandle,
        stderr: FileHandle,
        stdoutData: inout Data,
        stderrData: inout Data,
        lock: NSLock
    ) {
        stdout.readabilityHandler = nil
        stderr.readabilityHandler = nil
        for _ in 0..<3 {
            lock.lock()
            let outChunk = stdout.availableData
            let errChunk = stderr.availableData
            if !outChunk.isEmpty {
                stdoutData.append(outChunk)
            }
            if !errChunk.isEmpty {
                stderrData.append(errChunk)
            }
            lock.unlock()
            if outChunk.isEmpty && errChunk.isEmpty {
                break
            }
        }
    }

    private static func formatOutput(_ text: String) -> String {
        let collapsed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count <= outputLimit {
            return collapsed
        }
        return String(collapsed.prefix(outputLimit))
    }
}
