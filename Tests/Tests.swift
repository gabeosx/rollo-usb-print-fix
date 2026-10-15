import Foundation

// Synthetic PPD: intentionally contains no vendor PPD text or shipping data.
let synthetic = """
*PPD-Adobe: "4.3"
*Manufacturer: "Rollo"
*cupsFilter: "application/vnd.cups-raster 0 /Library/Printers/Rollo/rastertorollo"
*DefaultResolution: 600dpi
*Resolution 203dpi/203 dpi: "test"
*DefaultPageSize: 4x8
*DefaultroDarkness: 5
*% byte-preservation: é

"""

final class FakeSystem: RepairSystem {
    var driver = true
    var items: [Queue]
    var saved: [String: Record] = [:]
    var journal: Recovery?
    var failApply: String?
    var failRestore: String?
    var jobsArrive = false
    var jobAfterResume: String?
    var operations: [String] = []
    init(_ items: [Queue]) { self.items = items }
    func vendorAvailable() -> Bool { driver }
    func queues() throws -> [Queue] { items }
    func pendingJobs(_ name: String) throws -> Int { jobsArrive ? 1 : items.first { $0.name == name }!.jobs }
    func setAccepting(_ name: String, _ value: Bool) throws {
        operations.append("accept \(name) \(value)")
        items[items.firstIndex { $0.name == name }!].accepting = value
    }
    func setEnabled(_ name: String, _ value: Bool) throws {
        operations.append("enable \(name) \(value)")
        if failRestore == name && value { throw RepairError(99, "injected restore failure") }
        items[items.firstIndex { $0.name == name }!].enabled = value
        if jobAfterResume == name && value { items[items.firstIndex { $0.name == name }!].jobs = 1 }
    }
    func validate(_ ppd: String) throws {
        guard PPD.filter(ppd) != nil else { throw RepairError(99, "bad PPD") }
    }
    func applyPPD(_ name: String, _ ppd: String) throws {
        operations.append("ppd \(name)")
        if failApply == name { failApply = nil; throw RepairError(99, "injected apply failure") }
        items[items.firstIndex { $0.name == name }!].ppd = ppd
    }
    func records() throws -> [String: Record] { saved }
    func saveRecords(_ records: [String: Record]) throws { saved = records }
    func saveRecovery(_ recovery: Recovery) throws { journal = recovery }
    func recovery() throws -> Recovery? { journal }
    func finishRecovery() throws { journal = nil }
}

func queue(_ name: String = "Shipping_Station_2", enabled: Bool = true, accepting: Bool = true, usb: Bool = true, jobs: Int = 0, ppd: String = synthetic) -> Queue {
    Queue(name: name, identity: name, usb: usb, ppd: ppd, enabled: enabled, accepting: accepting, jobs: jobs)
}

@main struct Tests {
    static func main() throws {
        var passed = 0
        func test(_ name: String, _ body: () throws -> Void) throws {
            try body(); passed += 1; print("PASS \(name)")
        }
        func expect(_ condition: @autoclosure () -> Bool, _ message: String = "assertion failed") throws {
            if !condition() { throw RepairError(99, message) }
        }
        func fails(_ code: Int32, _ body: () throws -> Void) throws {
            do { try body(); throw RepairError(98, "expected error \(code)") }
            catch let error as RepairError { try expect(error.code == code, "expected \(code), got \(error)") }
        }
        try test("discovers custom queue names, preserves paper and darkness, sets 203 dpi") {
            let sys = FakeSystem([queue()]); let original = sys.items
            try Repair(sys).apply(removing: false)
            try expect(PPD.filter(sys.items[0].ppd) == Paths.filter)
            try expect(PPD.resolution(sys.items[0].ppd) == "203dpi")
            try expect(sys.items[0].ppd.contains("*DefaultPageSize: 4x8"))
            try expect(sys.items[0].ppd.contains("*DefaultroDarkness: 5"))
            try Repair(sys).apply(removing: true)
            try expect(sys.items == original, "uninstall did not restore original settings/states")
        }
        try test("multiple queues with independent paused and accepting states") {
            let sys = FakeSystem([queue("A"), queue("B", enabled: false), queue("C", accepting: false)])
            let states = sys.items.map { [$0.enabled, $0.accepting] }
            try Repair(sys).apply(removing: false)
            try expect(sys.items.map { [$0.enabled, $0.accepting] } == states)
            try expect(sys.items.allSatisfy { PPD.filter($0.ppd) == Paths.filter })
        }
        try test("scope excludes Wi-Fi, AirPrint, and non-Rollo printers") {
            let network = queue("Network", usb: false)
            let airprint = queue("AirPrint", ppd: synthetic.replacingOccurrences(of: Paths.vendor, with: "airprint"))
            let other = queue("Other", ppd: synthetic.replacingOccurrences(of: "\"Rollo\"", with: "\"Other\""))
            let sys = FakeSystem([network, airprint, other, queue("USB")])
            try Repair(sys).apply(removing: false)
            try expect(Array(sys.items.prefix(3)) == [network, airprint, other])
        }
        try test("missing driver refuses without mutations") {
            let sys = FakeSystem([queue()]); sys.driver = false
            try fails(10) { try Repair(sys).apply(removing: false) }
            try expect(sys.operations.isEmpty && sys.journal == nil)
        }
        try test("missing compatible queue refuses without mutations") {
            let sys = FakeSystem([queue(usb: false)])
            try fails(11) { try Repair(sys).apply(removing: false) }
            try expect(sys.operations.isEmpty)
        }
        try test("pending and held jobs refuse without canceling or pausing") {
            let sys = FakeSystem([queue(jobs: 1)])
            try fails(12) { try Repair(sys).apply(removing: false) }
            try expect(sys.operations.isEmpty)
        }
        try test("job arriving after preflight restores original states") {
            let sys = FakeSystem([queue()]); let before = sys.items; sys.jobsArrive = true
            try fails(12) { try Repair(sys).apply(removing: false) }
            try expect(sys.items == before && sys.journal == nil)
            try expect(!sys.operations.contains(where: { $0.hasPrefix("ppd") }))
        }
        try test("second-queue failure rolls back first queue and state manifest") {
            let sys = FakeSystem([queue("A"), queue("B")]); let before = sys.items
            sys.failApply = "B"
            try fails(99) { try Repair(sys).apply(removing: false) }
            try expect(sys.items == before && sys.saved.isEmpty && sys.journal == nil)
        }
        try test("reinstall keeps original restore settings") {
            let sys = FakeSystem([queue()]); let before = sys.items
            try Repair(sys).apply(removing: false); let firstRecord = sys.saved
            try Repair(sys).apply(removing: false)
            try expect(sys.saved == firstRecord)
            try Repair(sys).apply(removing: true)
            try expect(sys.items == before)
        }
        try test("uninstall preserves resolution changed by an administrator") {
            let sys = FakeSystem([queue()]); try Repair(sys).apply(removing: false)
            sys.items[0].ppd = sys.items[0].ppd.replacingOccurrences(of: "*DefaultResolution: 203dpi", with: "*DefaultResolution: 300dpi")
            try Repair(sys).apply(removing: true)
            try expect(PPD.resolution(sys.items[0].ppd) == "300dpi")
        }
        try test("explicit selection affects only selected queue") {
            let sys = FakeSystem([queue("A"), queue("B")]); let before = sys.items[1]
            try Repair(sys).apply(removing: false, selected: ["A"])
            try expect(sys.items[1] == before)
            try fails(11) { try Repair(sys).apply(removing: false, selected: ["Missing"]) }
        }
        try test("adopts old local wrapper without depending on personal queue name") {
            let sys = FakeSystem([queue(ppd: synthetic.replacingOccurrences(of: Paths.vendor, with: Paths.legacy))])
            try Repair(sys).apply(removing: false)
            try expect(PPD.filter(sys.items[0].ppd) == Paths.filter)
        }
        try test("interrupted package prepare can recover original states") {
            let sys = FakeSystem([queue()]); let original = sys.items
            try Repair(sys).prepare(removing: false)
            try expect(!sys.items[0].enabled && !sys.items[0].accepting && sys.journal != nil)
            try Repair(sys).rollback(sys.journal!)
            try expect(sys.items == original && sys.saved.isEmpty && sys.journal == nil)
        }
        try test("new installer refuses to overwrite interrupted setup journal") {
            let sys = FakeSystem([queue()]); try Repair(sys).prepare(removing: false)
            try fails(16) { try Repair(sys).prepare(removing: false) }
        }
        try test("rollback failure retains recovery journal") {
            let sys = FakeSystem([queue()]); sys.failRestore = sys.items[0].name
            try fails(16) { try Repair(sys).apply(removing: false) }
            try expect(sys.journal != nil)
        }
        try test("concurrent external PPD edit is not overwritten") {
            let sys = FakeSystem([queue()]); try Repair(sys).prepare(removing: false)
            sys.items[0].ppd += "*% external edit\n"
            let external = sys.items[0].ppd
            try fails(16) { try Repair(sys).commit(removing: false) }
            try expect(sys.items[0].ppd == external && sys.journal != nil)
        }
        try test("additional filter chains are excluded") {
            let sys = FakeSystem([queue(ppd: synthetic + "*cupsFilter2: \"something\"\n")])
            try fails(11) { try Repair(sys).apply(removing: false) }
        }
        try test("unknown chains referencing pacing block a misleading no-op uninstall") {
            let text = synthetic.replacingOccurrences(of: Paths.vendor, with: Paths.filter) + "*cupsFilter2: \"something\"\n"
            let sys = FakeSystem([queue(ppd: text)])
            try fails(13) { try Repair(sys).apply(removing: true) }
            try expect(sys.operations.isEmpty)
        }
        try test("filter declarations tolerate trailing whitespace") {
            let sys = FakeSystem([queue(ppd: synthetic.replacingOccurrences(of: Paths.vendor + "\"", with: Paths.vendor + "\"  "))])
            try Repair(sys).apply(removing: false)
            try expect(PPD.filter(sys.items[0].ppd) == Paths.filter)
        }
        try test("queue-name argument validation blocks paths and options") {
            let sys = MacSystem()
            for name in ["", "..", "-p", "a/b", "two words", "a\nb", "a\0b"] { try expect(!sys.validName(name)) }
            try expect(sys.validName("Shipping_2-West"))
        }
        try test("PPD byte encoding survives unmodified round trip") {
            let bytes = Data([0x25, 0x20, 0xa9, 0xe9, 0x0a])
            let text = String(data: bytes, encoding: .isoLatin1)!
            try expect(text.data(using: .isoLatin1) == bytes)
        }
        try test("recreated queue with a different device gets a fresh restore record") {
            let sys = FakeSystem([queue()]); try Repair(sys).apply(removing: false)
            sys.items[0] = queue(ppd: synthetic.replacingOccurrences(of: "600dpi", with: "300dpi"))
            sys.items[0].identity = "new-device"
            try Repair(sys).apply(removing: false)
            try Repair(sys).apply(removing: true)
            try expect(PPD.resolution(sys.items[0].ppd) == "300dpi")
        }
        try test("reinstall after a changed resolution records the newer administrator setting") {
            let sys = FakeSystem([queue()]); try Repair(sys).apply(removing: false)
            sys.items[0].ppd = sys.items[0].ppd.replacingOccurrences(of: "*DefaultResolution: 203dpi", with: "*DefaultResolution: 300dpi")
            try Repair(sys).apply(removing: false)
            try Repair(sys).apply(removing: true)
            try expect(PPD.resolution(sys.items[0].ppd) == "300dpi")
        }
        try test("an arriving job during an idempotent reinstall needs no driver rollback") {
            let sys = FakeSystem([queue()]); try Repair(sys).apply(removing: false)
            let before = sys.items; sys.jobsArrive = true
            try fails(12) { try Repair(sys).apply(removing: false) }
            try expect(sys.items == before && sys.journal == nil)
        }
        try test("rollback does not replace the driver under a newly started print job") {
            let sys = FakeSystem([queue("A"), queue("B")])
            sys.jobAfterResume = "A"; sys.failRestore = "B"
            try fails(16) { try Repair(sys).apply(removing: false) }
            try expect(sys.items[0].jobs == 1 && PPD.filter(sys.items[0].ppd) == Paths.filter)
            try expect(!sys.items[0].accepting && sys.journal != nil)
        }
        print("\(passed) meaningful installer/recovery tests passed. No live queue changes or paper used.")
    }
}
