import CoreAudio
import Foundation

/// Lists audio devices and switches the system default input/output/alert device
/// via Core Audio (`kAudioHardwarePropertyDefault*Device`).
enum AudioManager {

    /// The three system default roles that can be switched independently.
    enum Role {
        case output      // main sound output
        case input       // sound input
        case systemOutput // alert / sound-effects output ("Alerts")

        var defaultSelector: AudioObjectPropertySelector {
            switch self {
            case .output: return kAudioHardwarePropertyDefaultOutputDevice
            case .input: return kAudioHardwarePropertyDefaultInputDevice
            case .systemOutput: return kAudioHardwarePropertyDefaultSystemOutputDevice
            }
        }

        /// The stream scope a device must have channels in to be a candidate.
        var streamScope: AudioObjectPropertyScope {
            self == .input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        }
    }

    struct Device: Identifiable {
        let id: AudioDeviceID
        let name: String
        let isDefault: Bool
    }

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    /// Devices eligible for the given role, sorted by name, with the current
    /// default flagged.
    static func devices(for role: Role) -> [Device] {
        let current = defaultDevice(for: role)
        return allDeviceIDs()
            .filter { hasChannels($0, scope: role.streamScope) }
            .map { Device(id: $0, name: name(of: $0), isDefault: $0 == current) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Make the given device the system default for the role.
    @discardableResult
    static func setDefault(_ id: AudioDeviceID, for role: Role) -> Bool {
        var address = makeAddress(role.defaultSelector)
        var device = id
        let status = AudioObjectSetPropertyData(
            system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device
        )
        if status != noErr {
            NSLog("OpenSwitch: failed to set audio device (status \(status))")
        }
        return status == noErr
    }

    // MARK: - Core Audio helpers

    private static func makeAddress(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultDevice(for role: Role) -> AudioDeviceID {
        var address = makeAddress(role.defaultSelector)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device)
        return device
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = makeAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func name(of id: AudioDeviceID) -> String {
        var address = makeAddress(kAudioObjectPropertyName)
        var cfName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &cfName) == noErr,
              let name = cfName?.takeRetainedValue() else {
            return "Unknown Device"
        }
        return name as String
    }

    /// True if the device has at least one channel in the given scope (input/output).
    private static func hasChannels(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = makeAddress(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }

        let data = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { data.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, data) == noErr else { return false }

        let list = UnsafeMutableAudioBufferListPointer(data.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }
}
