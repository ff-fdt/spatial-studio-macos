import AppKit
import CoreAudio
import Darwin

struct AudioInput: Identifiable, Equatable {
    let id: String
    let name: String
    var pids: [AudioObjectID]
    var bundle: String?
}

@MainActor
enum AudioInputs {
    static func current(keeping requested: Set<String>) -> [AudioInput] {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != getpid() && !$0.isTerminated &&
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
        }
        var entries: [String: AudioInput] = [:]
        var owners: [(String, NSRunningApplication)] = []
        for app in apps {
            guard let id = app.bundleIdentifier else { continue }
            entries[id] = AudioInput(id: id, name: app.localizedName ?? id, pids: [], bundle: id)
            owners.append((id, app))
        }
        owners.sort { $0.0.count > $1.0.count }
        for process in audioProcesses() {
            let pid = scalar(process, kAudioProcessPropertyPID, initial: pid_t(0))
            guard pid != 0, pid != getpid() else { continue }
            let bundle = identifier(process)
            let appPath = processPath(pid)
            let owner = owners.first { id, app in
                if app.processIdentifier == pid || bundle == id || bundle.hasPrefix(id + ".") { return true }
                guard let root = app.bundleURL?.path, let appPath else { return false }
                return appPath.hasPrefix(root + "/")
            }
            if let (id, _) = owner {
                entries[id]?.pids.append(process)
            } else if bundle.hasPrefix("com.apple.WebKit."),
                      requested.contains("process:\(pid)") ||
                      scalar(process, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0)) != 0 {
                // WebKit's shared GPU helper may not expose its owning app through
                // the public process API. Keep each active helper separately selectable.
                let id = "process:\(pid)"
                entries[id] = AudioInput(id: id, name: tr("WebKit 音频") + " · \(pid)", pids: [process], bundle: nil)
            }
        }
        return entries.values.map {
            AudioInput(id: $0.id, name: $0.name, pids: Array(Set($0.pids)).sorted(), bundle: $0.bundle)
        }.sorted {
            let name = $0.name.localizedStandardCompare($1.name)
            return name == .orderedSame ? $0.id < $1.id : name == .orderedAscending
        }
    }

    private static func audioProcesses() -> [AudioObjectID] {
        var address = addressFor(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        let status = ids.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, buffer.baseAddress!)
        }
        guard status == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride))
    }

    private static func addressFor(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func scalar<T>(_ process: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T) -> T {
        var address = addressFor(selector)
        var result = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutableBytes(of: &result) { buffer in
            AudioObjectGetPropertyData(process, &address, 0, nil, &size, buffer.baseAddress!)
        }
        return status == noErr ? result : initial
    }

    private static func identifier(_ process: AudioObjectID) -> String {
        var address = addressFor(kAudioProcessPropertyBundleID)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &cf) == noErr else { return "" }
        return (cf?.takeRetainedValue() as String?) ?? ""
    }

    private static func processPath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix(while: { $0 != 0 }).map(UInt8.init(bitPattern:)), as: UTF8.self)
    }
}
