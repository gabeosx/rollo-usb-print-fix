// SPDX-License-Identifier: MIT
// Run actual Installer JavaScript against a small read-only host model.
import Foundation
import JavaScriptCore

@main struct InstallerChecks {
    static func main() throws {
        var count = 0
        func check(_ file: String, _ function: String, _ paths: [String], expected: Bool) throws {
            let xml = try String(contentsOfFile: file, encoding: .utf8)
            guard let begin = xml.range(of: "<![CDATA["), let end = xml.range(of: "]]>", range: begin.upperBound..<xml.endIndex) else {
                throw NSError(domain: "InstallerChecks", code: 1)
            }
            let script = String(xml[begin.upperBound..<end.lowerBound])
            let context = JSContext()!
            let pathsJSON = String(data: try JSONSerialization.data(withJSONObject: paths), encoding: .utf8)!
            context.evaluateScript("var existing = \(pathsJSON); var system = {files:{fileExistsAtPath:function(p){return existing.indexOf(p) !== -1;}}}; var my = {result:{},target:{mountpoint:'/'}};")
            context.evaluateScript(script)
            let actual = context.evaluateScript(function + "()")!.toBool()
            guard context.exception == nil, actual == expected else { throw NSError(domain: "InstallerChecks", code: 2) }
            let valid = context.evaluateScript(expected
                ? "my.result.type !== 'Fatal'"
                : "my.result.type === 'Fatal' && typeof my.result.message === 'string' && my.result.message.length > 0")!.toBool()
            guard valid else { throw NSError(domain: "InstallerChecks", code: 3) }
            count += 1
            print("PASS \(file): \(expected ? "success has no fatal result" : "failure supplies an actionable message")")
        }
        let driver = "/Library/Printers/Rollo/rastertorollo"
        let recovery = "/Library/Application Support/Rollo USB Pacing/recovery.json"
        try check("Packaging/Distribution.xml", "checkSetup", [driver], expected: true)
        try check("Packaging/Distribution.xml", "checkSetup", [], expected: false)
        try check("Packaging/Distribution.xml", "checkSetup", [driver, recovery], expected: false)
        try check("Packaging/Uninstall.xml", "checkRemoval", [], expected: true)
        try check("Packaging/Uninstall.xml", "checkRemoval", [recovery], expected: false)
        print("\(count) Installer JavaScript checks passed.")
    }
}
