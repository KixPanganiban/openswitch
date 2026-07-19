import AppKit

/// A single captured clipboard entry.
struct ClipboardEntry: Identifiable {
    enum Content {
        case text(String)
        case image(NSImage)
    }
    let id = UUID()
    let content: Content
}

/// Maintains a short in-memory history of the general pasteboard.
///
/// macOS keeps no clipboard history and emits no "pasteboard changed" event, so
/// this polls `NSPasteboard.general.changeCount` on a timer — the same approach
/// every clipboard manager uses. History is memory-only (never written to disk),
/// and items marked concealed/transient (passwords and other sensitive copies)
/// are skipped.
final class ClipboardManager {
    private(set) var history: [ClipboardEntry] = []

    private let maxItems = 20
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    /// Conventional types apps set to opt a copy out of history managers.
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    /// Begin polling. Captures whatever is currently on the pasteboard first.
    func start() {
        guard timer == nil else { return }
        capture()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // .common so polling continues even while a menu or other tracking loop is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func clear() {
        history.removeAll()
    }

    /// Re-copy an entry to the pasteboard and move it to the top of the history.
    func copyToPasteboard(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        switch entry.content {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .image(let image):
            pasteboard.writeObjects([image])
        }
        // Don't re-capture our own write on the next poll.
        lastChangeCount = pasteboard.changeCount
        moveToTop(entry)
    }

    // MARK: - Polling

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        capture()
    }

    private func capture() {
        let types = Set(pasteboard.types ?? [])

        // Skip passwords and other explicitly sensitive/transient copies.
        if types.contains(Self.concealed) || types.contains(Self.transient) { return }

        // Prefer an image (screenshots, "Copy Image" from a browser) over any
        // incidental text representation.
        if types.contains(.png) || types.contains(.tiff),
           let image = NSImage(pasteboard: pasteboard) {
            add(.image(image))
            return
        }

        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.text(string))
        }
    }

    private func add(_ content: ClipboardEntry.Content) {
        // Collapse consecutive duplicate text.
        if case .text(let new) = content,
           case .text(let top)? = history.first?.content,
           new == top {
            return
        }
        history.insert(ClipboardEntry(content: content), at: 0)
        while history.count > maxItems {
            history.removeLast()
        }
    }

    private func moveToTop(_ entry: ClipboardEntry) {
        if let index = history.firstIndex(where: { $0.id == entry.id }) {
            history.remove(at: index)
        }
        history.insert(entry, at: 0)
    }
}
