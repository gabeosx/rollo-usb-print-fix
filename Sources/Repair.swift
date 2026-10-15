// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rollo USB Pacing contributors

import Foundation
import CryptoKit
import Darwin

enum Paths {
    static let vendor = "/Library/Printers/Rollo/rastertorollo"
    static let filter = "/Library/Printers/RolloPacing/rastertorollo-paced"
    static let legacy = "/Library/Printers/Rollo/rastertorollo-paced"
    static let support = "/Library/Application Support/Rollo USB Pacing"
    static let tool = support + "/rollo-pacing"
}

struct RepairError: Error, CustomStringConvertible {
    let code: Int32
    let description: String
    init(_ code: Int32, _ message: String) { self.code = code; description = message }
}

struct Queue: Equatable {
    var name: String
    var identity: String
    var usb: Bool
    var ppd: String
    var enabled: Bool
    var accepting: Bool
    var jobs: Int
}

struct Record: Codable, Equatable {
    var identity: String
    var originalResolution: String?
    var changedResolution: Bool
}

struct Snapshot: Codable {
    var identity: String
    var usb: Bool
    var name: String
    var ppd: String
    var enabled: Bool
    var accepting: Bool
}

struct Recovery: Codable {
    var version: Int = 1
    var removing: Bool
    var snapshots: [Snapshot]
    var originalRecords: [String: Record]
    var proposedRecords: [String: Record]
    var replacements: [String: String]
}

protocol RepairSystem: AnyObject {
    func vendorAvailable() -> Bool
    func queues() throws -> [Queue]
    func pendingJobs(_ name: String) throws -> Int
    func setAccepting(_ name: String, _ value: Bool) throws
    func setEnabled(_ name: String, _ value: Bool) throws
    func validate(_ ppd: String) throws
    func applyPPD(_ name: String, _ ppd: String) throws
    func records() throws -> [String: Record]
    func saveRecords(_ records: [String: Record]) throws
    func saveRecovery(_ recovery: Recovery) throws
    func recovery() throws -> Recovery?
    func finishRecovery() throws
}

enum PPD {
    static let vendorLine = "*cupsFilter: \"application/vnd.cups-raster 0 \(Paths.vendor)\""
    static let filterLine = "*cupsFilter: \"application/vnd.cups-raster 0 \(Paths.filter)\""
    static let legacyLine = "*cupsFilter: \"application/vnd.cups-raster 0 \(Paths.legacy)\""
    static func lines(_ text: String) -> [String] { text.components(separatedBy: .newlines) }
    static func filter(_ text: String) -> String? {
        let filters = lines(text).filter { $0.hasPrefix("*cupsFilter:") || $0.hasPrefix("*cupsFilter2:") }
        guard filters.count == 1 else { return nil }
        // Whitespace differences are allowed, but MIME type, cost and executable must match exactly.
        let parts = filters[0].trimmingCharacters(in: .whitespaces).split(separator: "\"")
        guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "*cupsFilter:" else { return nil }
        let fields = parts[1].split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count == 3, fields[0] == "application/vnd.cups-raster", fields[1] == "0" else { return nil }
        return fields[2]
    }
    static func isRollo(_ text: String) -> Bool {
        lines(text).contains { $0.trimmingCharacters(in: .whitespaces) == "*Manufacturer: \"Rollo\"" }
    }
    static func managed(_ text: String) -> Bool {
        [Paths.filter, Paths.legacy].contains(filter(text) ?? "")
    }
    static func supported(_ queue: Queue) -> Bool {
        queue.usb && isRollo(queue.ppd) && [Paths.vendor, Paths.filter, Paths.legacy].contains(filter(queue.ppd) ?? "")
    }
    static func resolution(_ text: String) -> String? {
        lines(text).first { $0.hasPrefix("*DefaultResolution:") }?
            .dropFirst("*DefaultResolution:".count).trimmingCharacters(in: .whitespaces)
    }
    static func replacing(_ text: String, filter: String, resolution: String? = nil) -> String {
        lines(text).map { line in
            if line.hasPrefix("*cupsFilter:") { return "*cupsFilter: \"application/vnd.cups-raster 0 \(filter)\"" }
            if let resolution, line.hasPrefix("*DefaultResolution:") { return "*DefaultResolution: \(resolution)" }
            return line
        }.joined(separator: "\n")
    }
    static func has203(_ text: String) -> Bool { lines(text).contains { $0.hasPrefix("*Resolution 203dpi/") || $0.hasPrefix("*Resolution 203dpi:") } }
}

final class Repair {
    let system: RepairSystem
    init(_ system: RepairSystem) { self.system = system }

    func candidates(removing: Bool, selected: Set<String> = []) throws -> [Queue] {
        guard removing || system.vendorAvailable() else {
            throw RepairError(10, "Install the official Rollo USB macOS driver first, then add the USB printer in System Settings > Printers & Scanners. The original converter is missing or has unsafe permissions.")
        }
        let all = try system.queues()
        let matches = all.filter { removing ? PPD.managed($0.ppd) : PPD.supported($0) }
        let chosen = matches.filter { selected.isEmpty || selected.contains($0.name) }
        guard !chosen.isEmpty else {
            if removing && all.contains(where: { $0.ppd.contains(Paths.filter) || $0.ppd.contains(Paths.legacy) }) {
                throw RepairError(13, "A printer references pacing in an unfamiliar filter chain. No changes were made. Ask an administrator to review that queue before removing the filter.")
            }
            throw RepairError(11, removing ? "No printer queues currently use this pacing filter. Nothing needs to be changed." : "No compatible USB Rollo queue was found. Install the official USB driver, connect by USB, and add the printer in System Settings > Printers & Scanners. Wi-Fi, AirPrint, and other driver versions are not supported.")
        }
        guard selected.isSubset(of: Set(chosen.map(\.name))) else {
            throw RepairError(11, "A selected queue is missing or unsupported. Run status to check the queue names.")
        }
        guard system.vendorAvailable() else {
            throw RepairError(10, "Reinstall the official Rollo USB driver before removing the fix; the original converter is required to restore printing.")
        }
        for queue in chosen where queue.jobs != 0 {
            throw RepairError(12, "\(queue.name) has pending or held print jobs. Finish or cancel them in Print Center, then run this installer again. No jobs will be canceled automatically.")
        }
        return chosen.sorted { $0.name < $1.name }
    }

    func prepare(removing: Bool, selected: Set<String> = []) throws {
        guard try system.recovery() == nil else {
            throw RepairError(16, "A previous setup was interrupted. Run the recovery command in the administrator guide before trying again.")
        }
        let queues = try candidates(removing: removing, selected: selected)
        var records = try system.records()
        let originalRecords = records
        var replacements: [String: String] = [:]
        for queue in queues {
            if removing {
                let record = records[queue.name]?.identity == queue.identity ? records[queue.name] : nil
                let restore = record?.changedResolution == true && PPD.resolution(queue.ppd) == "203dpi"
                    ? record?.originalResolution : nil
                replacements[queue.name] = PPD.replacing(queue.ppd, filter: Paths.vendor, resolution: restore)
                records.removeValue(forKey: queue.name)
            } else {
                let old = PPD.resolution(queue.ppd)
                let change = PPD.has203(queue.ppd) && old != nil && old != "203dpi"
                if records[queue.name]?.identity != queue.identity || change {
                    records[queue.name] = Record(identity: queue.identity, originalResolution: old, changedResolution: change)
                }
                replacements[queue.name] = PPD.replacing(queue.ppd, filter: Paths.filter, resolution: change ? "203dpi" : nil)
            }
            try system.validate(replacements[queue.name]!)
        }
        let snapshots = queues.map { Snapshot(identity: $0.identity, usb: $0.usb, name: $0.name, ppd: $0.ppd, enabled: $0.enabled, accepting: $0.accepting) }
        let recovery = Recovery(removing: removing, snapshots: snapshots, originalRecords: originalRecords,
                                proposedRecords: records, replacements: replacements)
        try system.saveRecovery(recovery)
        do {
            // Quiesce before Installer replaces any executable, and never cancel jobs.
            for queue in queues { try system.setAccepting(queue.name, false) }
            for queue in queues {
                guard try system.pendingJobs(queue.name) == 0 else {
                    throw RepairError(12, "A job arrived on \(queue.name) during setup. Let it finish, then try again.")
                }
            }
            for queue in queues { try system.setEnabled(queue.name, false) }
        } catch {
            try rollback(recovery, because: error)
        }
    }

    func rollback(_ recovery: Recovery, because original: Error? = nil) throws {
        var failures: [String] = []
        for snapshot in recovery.snapshots {
            do { try system.setAccepting(snapshot.name, false) }
            catch { failures.append(snapshot.name) }
        }
        for snapshot in recovery.snapshots.reversed() {
            do {
                let current = try system.queues().first { $0.name == snapshot.name }
                guard let current, current.identity == snapshot.identity else { throw RepairError(16, "Queue removed or replaced during setup.") }
                if current.ppd == snapshot.ppd {
                    // No driver change to undo (including an idempotent reinstall).
                } else if current.ppd == recovery.replacements[snapshot.name] {
                    guard try system.pendingJobs(snapshot.name) == 0 else { throw RepairError(12, "A new job prevents driver rollback.") }
                    try system.applyPPD(snapshot.name, snapshot.ppd)
                } else {
                    // A different administrator changed the driver. Do not overwrite it.
                    throw RepairError(16, "Queue changed outside setup.")
                }
                try system.setEnabled(snapshot.name, snapshot.enabled)
                try system.setAccepting(snapshot.name, snapshot.accepting)
            } catch { failures.append(snapshot.name) }
        }
        do { try system.saveRecords(recovery.originalRecords) } catch { failures.append("settings record") }
        guard failures.isEmpty else {
            throw RepairError(16, "Setup/recovery was incomplete for: \(failures.joined(separator: ", ")). Stop printing. Contact your administrator; recovery files were retained. See the administrator guide.")
        }
        try system.finishRecovery()
        if let original { throw original }
    }

    @discardableResult
    func commit(removing: Bool) throws -> [String] {
        guard let recovery = try system.recovery(), recovery.version == 1, recovery.removing == removing else {
            throw RepairError(16, "No matching prepared setup was found. Run the installer again, or use recover for an interrupted setup.")
        }
        do {
            for snapshot in recovery.snapshots {
                guard let current = try system.queues().first(where: { $0.name == snapshot.name }),
                      current.ppd == snapshot.ppd, current.usb == snapshot.usb, current.identity == snapshot.identity,
                      !current.accepting, !current.enabled, try system.pendingJobs(snapshot.name) == 0 else {
                    throw RepairError(13, "\(snapshot.name) changed during setup. Check the printer configuration and retry.")
                }
                guard let ppd = recovery.replacements[snapshot.name] else { throw RepairError(16, "Incomplete recovery record.") }
                try system.validate(ppd)
            }
            for snapshot in recovery.snapshots { try system.applyPPD(snapshot.name, recovery.replacements[snapshot.name]!) }
            try system.saveRecords(recovery.proposedRecords)
            for snapshot in recovery.snapshots {
                try system.setEnabled(snapshot.name, snapshot.enabled)
                try system.setAccepting(snapshot.name, snapshot.accepting)
            }
            try system.finishRecovery()
        } catch { try rollback(recovery, because: error) }
        return recovery.snapshots.map(\.name)
    }

    @discardableResult
    func apply(removing: Bool, selected: Set<String> = []) throws -> [String] {
        try prepare(removing: removing, selected: selected)
        return try commit(removing: removing)
    }

}

final class MacSystem: RepairSystem {
    let fm = FileManager.default

    func run(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "LANG": "C", "HOME": NSHomeDirectory(), "CUPS_SERVER": "/private/var/run/cupsd"]
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 25, execute: timeout)
        let hardTimeout = DispatchWorkItem { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 28, execute: hardTimeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel(); hardTimeout.cancel()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw RepairError(14, "\(URL(fileURLWithPath: path).lastPathComponent) failed. \(text.prefix(1000))")
        }
        return text
    }

    func safeFile(_ path: String, executable: Bool = false) -> Bool {
        var parent = (path as NSString).deletingLastPathComponent
        while parent != "/" {
            guard let attrs = try? fm.attributesOfItem(atPath: parent),
                  attrs[.type] as? FileAttributeType == .typeDirectory,
                  (attrs[.ownerAccountID] as? NSNumber)?.intValue == 0,
                  let mode = attrs[.posixPermissions] as? NSNumber, mode.intValue & 0o022 == 0 else { return false }
            parent = (parent as NSString).deletingLastPathComponent
        }
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.ownerAccountID] as? NSNumber)?.intValue == 0,
              let mode = attrs[.posixPermissions] as? NSNumber, mode.intValue & 0o022 == 0 else { return false }
        return !executable || fm.isExecutableFile(atPath: path)
    }
    func vendorAvailable() -> Bool { safeFile(Paths.vendor, executable: true) }
    func validName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("-") && name != "." && name != ".." &&
        !name.contains(where: { $0 == "/" || $0 == "\0" || $0.isNewline || $0.isWhitespace })
    }
    func queues() throws -> [Queue] {
        let devices: String
        do { devices = try run("/usr/bin/lpstat", ["-v"]) }
        catch let error as RepairError where error.description.contains("No destinations added") { return [] }
        let statuses = try run("/usr/bin/lpstat", ["-p"])
        let accepting = try run("/usr/bin/lpstat", ["-a"])
        var result: [Queue] = []
        for line in devices.components(separatedBy: .newlines) where line.hasPrefix("device for ") {
            let fields = line.dropFirst("device for ".count).components(separatedBy: ": ")
            guard fields.count == 2, validName(fields[0]) else { continue }
            let name = fields[0]
            let ppdPath = "/private/etc/cups/ppd/\(name).ppd"
            guard safeFile(ppdPath), let data = fm.contents(atPath: ppdPath) else { continue }
            let ppd = String(data: data, encoding: .isoLatin1) ?? ""
            guard let status = statuses.components(separatedBy: .newlines).first(where: { $0.hasPrefix("printer \(name) ") }),
                  let accept = accepting.components(separatedBy: .newlines).first(where: { $0.hasPrefix("\(name) ") }) else {
                throw RepairError(14, "Cannot determine the state of \(name). Restart Print Center and try again.")
            }
            let identity = SHA256.hash(data: Data(fields[1].utf8)).map { String(format: "%02x", $0) }.joined()
            result.append(Queue(name: name, identity: identity, usb: fields[1].hasPrefix("usb://"), ppd: ppd,
                                enabled: !status.contains(" disabled "), accepting: accept.hasPrefix("\(name) accepting requests"),
                                jobs: try pendingJobs(name)))
        }
        return result
    }
    func pendingJobs(_ name: String) throws -> Int {
        try run("/usr/bin/lpstat", ["-W", "not-completed", "-o", name]).split(whereSeparator: \.isNewline).count
    }
    func setAccepting(_ name: String, _ value: Bool) throws {
        _ = try run(value ? "/usr/sbin/cupsaccept" : "/usr/sbin/cupsreject", value ? [name] : ["-r", "Rollo USB Pacing setup in progress", name])
    }
    func setEnabled(_ name: String, _ value: Bool) throws {
        _ = try run(value ? "/usr/sbin/cupsenable" : "/usr/sbin/cupsdisable", value ? [name] : ["-r", "Paused state preserved by Rollo USB Pacing", name])
    }
    func withPPD<T>(_ text: String, _ action: (String) throws -> T) throws -> T {
        let directory = fm.temporaryDirectory.appendingPathComponent("rollo-pacing-" + UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: directory) }
        let file = directory.appendingPathComponent("queue.ppd")
        guard let bytes = text.data(using: .isoLatin1) else { throw RepairError(13, "PPD encoding is not supported.") }
        try bytes.write(to: file)
        return try action(file.path)
    }
    func validate(_ ppd: String) throws {
        // Syntax validation happens before the package has placed the filter on disk.
        try withPPD(ppd) { _ = try run("/usr/bin/cupstestppd", ["-I", "filters", "-q", $0]) }
    }
    func applyPPD(_ name: String, _ ppd: String) throws {
        try withPPD(ppd) { _ = try run("/usr/sbin/lpadmin", ["-p", name, "-P", $0]) }
        let actual = try queues().first { $0.name == name }
        guard actual.map({ PPD.filter($0.ppd) == PPD.filter(ppd) && PPD.resolution($0.ppd) == PPD.resolution(ppd) }) == true else {
            throw RepairError(14, "The updated driver settings for \(name) could not be verified.")
        }
    }
    func records() throws -> [String: Record] {
        let file = Paths.support + "/state.json"
        if !fm.fileExists(atPath: file) { return [:] }
        guard safeFile(file) else { throw RepairError(13, "The saved repair state has unsafe permissions. Contact your administrator.") }
        return try JSONDecoder().decode([String: Record].self, from: Data(contentsOf: URL(fileURLWithPath: file)))
    }
    func saveRecords(_ records: [String: Record]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: URL(fileURLWithPath: Paths.support + "/state.json"), options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.support + "/state.json")
    }
    func saveRecovery(_ recovery: Recovery) throws {
        let file = Paths.support + "/recovery.json"
        guard !fm.fileExists(atPath: file) else { throw RepairError(16, "A previous setup was interrupted. Run rollo-pacing recover as described in the administrator guide before trying again.") }
        let bytes = try JSONEncoder().encode(recovery)
        // Keep a local, root-readable recovery history. Never included in distribution/support exports.
        let backups = Paths.support + "/Backups"
        try secureDirectory(backups, mode: 0o700)
        let history = backups + "/" + UUID().uuidString + ".json"
        try bytes.write(to: URL(fileURLWithPath: history), options: .withoutOverwriting)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: history)
        try bytes.write(to: URL(fileURLWithPath: file), options: .withoutOverwriting)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file)
    }
    func recovery() throws -> Recovery? {
        let file = Paths.support + "/recovery.json"
        if !fm.fileExists(atPath: file) { return nil }
        guard safeFile(file) else { throw RepairError(13, "The recovery record has unsafe permissions.") }
        let record = try JSONDecoder().decode(Recovery.self, from: Data(contentsOf: URL(fileURLWithPath: file)))
        guard record.version == 1, !record.snapshots.isEmpty,
              record.snapshots.allSatisfy({ validName($0.name) }),
              Set(record.snapshots.map(\.name)).count == record.snapshots.count else {
            throw RepairError(16, "Unsupported or incomplete recovery record. Contact your administrator.")
        }
        return record
    }
    func finishRecovery() throws {
        try fm.removeItem(atPath: Paths.support + "/recovery.json")
    }

    func secureDirectory(_ path: String, mode: Int = 0o755) throws {
        // Walk every parent: privileged operations must never follow user-controlled links.
        var current = "/"
        for part in path.split(separator: "/") {
            current = (current as NSString).appendingPathComponent(String(part))
            if !fm.fileExists(atPath: current) {
                try fm.createDirectory(atPath: current, withIntermediateDirectories: false, attributes: [.posixPermissions: mode])
            }
            let attrs = try fm.attributesOfItem(atPath: current)
            guard attrs[.type] as? FileAttributeType == .typeDirectory,
                  (attrs[.ownerAccountID] as? NSNumber)?.intValue == 0,
                  let permissions = attrs[.posixPermissions] as? NSNumber, permissions.intValue & 0o022 == 0 else {
                throw RepairError(13, "Unsafe installation directory: \(current). Contact your administrator.")
            }
        }
    }

    func withLock<T>(_ action: () throws -> T) throws -> T {
        guard geteuid() == 0 else { throw RepairError(15, "This command needs administrator access. Use the installer package, or run this command with sudo.") }
        try secureDirectory(Paths.support)
        try secureDirectory("/Library/Printers/RolloPacing")
        let lock = Paths.support + "/setup.lock"
        let fd = open(lock, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw RepairError(13, "Cannot open the setup lock.") }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_uid == 0, st.st_mode & 0o022 == 0, st.st_mode & S_IFMT == S_IFREG,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw RepairError(13, "Another setup is running, or the setup lock is unsafe. Try again after it finishes.") }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }

    func recover() throws {
        guard let record = try recovery() else { throw RepairError(16, "No interrupted setup was found.") }
        // Recovery never interrupts or cancels queued jobs.
        for snapshot in record.snapshots {
            guard try pendingJobs(snapshot.name) == 0 else { throw RepairError(12, "Finish or cancel pending jobs before recovery.") }
        }
        for snapshot in record.snapshots { try setAccepting(snapshot.name, false) }
        for snapshot in record.snapshots {
            guard try pendingJobs(snapshot.name) == 0 else { throw RepairError(12, "A job arrived during recovery. Check Print Center and retry.") }
            try setEnabled(snapshot.name, false)
        }
        try Repair(self).rollback(record)
    }
}
