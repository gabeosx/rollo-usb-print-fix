// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rollo USB Pacing contributors

import Foundation
import Darwin

func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        print("Rollo USB Pacing\nCommands: status, preflight [install|uninstall], install, uninstall, recover\nInstall/uninstall accept repeated --queue QUEUE_NAME; omitted means all compatible queues.")
        return
    }
    let system = MacSystem()
    let repair = Repair(system)
    var selected: Set<String> = []
    var index = 1
    if command == "preflight" && arguments.count > 1 { index = 2 }
    while index < arguments.count {
        guard arguments[index] == "--queue", index + 1 < arguments.count, system.validName(arguments[index + 1]) else {
            throw RepairError(2, "Use --queue followed by an existing queue name, or omit it to select all compatible queues.")
        }
        selected.insert(arguments[index + 1]); index += 2
    }
    if !selected.isEmpty && ["status", "recover", "commit-install"].contains(command) {
        throw RepairError(2, "This command does not accept --queue. Use install or uninstall to select queues.")
    }
    switch command {
    case "status":
        print("Rollo USB Pacing — setup check (read-only)")
        print(system.vendorAvailable() ? "Official USB converter: found" : "Official USB converter: missing or unsafe; install the official Rollo USB driver first.")
        let queues = try system.queues()
        for queue in queues where PPD.isRollo(queue.ppd) || PPD.managed(queue.ppd) {
            let state = PPD.managed(queue.ppd) ? "PACING ENABLED" : (PPD.supported(queue) ? "compatible, pacing not installed" : "unsupported connection or driver")
            print("\(queue.name): \(state); \(queue.enabled ? "enabled" : "paused"), \(queue.accepting ? "accepting jobs" : "not accepting jobs"), \(queue.jobs) pending jobs; resolution \(PPD.resolution(queue.ppd) ?? "unknown").")
        }
        if !queues.contains(where: { PPD.supported($0) }) {
            print("No compatible USB Rollo queue found. Add the printer with the official USB driver. Wi-Fi and AirPrint are outside this repair's scope.")
        }
        print("This check does not print, upload data, or prove that a physical label printed correctly.")
    case "preflight":
        if system.fm.fileExists(atPath: Paths.support + "/recovery.json") {
            throw RepairError(16, "A previous setup was interrupted. Recover it before continuing; see the administrator guide.")
        }
        let mode = arguments.count > 1 ? arguments[1] : "install"
        guard ["install", "uninstall"].contains(mode) else { throw RepairError(2, "Use preflight install or preflight uninstall.") }
        let names = try repair.candidates(removing: mode == "uninstall", selected: selected).map(\.name)
        print("Ready: \(names.joined(separator: ", ")). No configuration changes made.")
    case "install", "uninstall", "prepare-install", "commit-install":
        try system.withLock {
            if command == "install" || command == "commit-install" {
                guard system.safeFile(Paths.filter, executable: true) else { throw RepairError(13, "The pacing filter is missing or has unsafe permissions. Reinstall the package.") }
            }
            if command == "prepare-install" {
                try repair.prepare(removing: false, selected: selected)
                print("Compatible queues prepared for package installation.")
                return
            }
            let names: [String]
            do {
                names = command == "commit-install" ? try repair.commit(removing: false) : try repair.apply(removing: command == "uninstall", selected: selected)
            } catch let error as RepairError where command == "uninstall" && error.code == 11 && selected.isEmpty {
                names = [] // Idempotent uninstall when no managed queues remain.
            }
            print("\(command != "uninstall" ? "Pacing enabled" : "Original converter restored") for: \(names.joined(separator: ", ")). Previous enabled/paused and accepting states preserved. No test labels were printed.")
            if try command == "uninstall" && selected.isEmpty && !system.queues().contains(where: { $0.ppd.contains(Paths.filter) }) {
                // Keep the small management tool and records for recovery, diagnosis and reinstall.
                if system.fm.fileExists(atPath: Paths.filter) { try system.fm.removeItem(atPath: Paths.filter) }
                print("Pacing executable removed. Management tool and recovery metadata retained.")
            }
        }
    case "recover":
        try system.withLock { try system.recover(); print("Interrupted setup recovered. Previous printer states restored.") }
    default: throw RepairError(2, "Unknown command. Run rollo-pacing without arguments for help.")
    }
}

do { try main() }
catch let error as RepairError { fputs("Rollo USB Pacing: \(error.description)\n", stderr); exit(error.code) }
catch { fputs("Rollo USB Pacing: \(error.localizedDescription)\n", stderr); exit(1) }
