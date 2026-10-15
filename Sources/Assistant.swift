// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rollo USB Pacing contributors

import AppKit

@main final class SetupApp: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let headline = NSTextField(wrappingLabelWithString: "Checking your printers…")
    let detail = NSTextView()
    let progress = NSProgressIndicator()
    let installButton = NSButton(title: "Install…", target: nil, action: nil)
    let removeButton = NSButton(title: "Remove…", target: nil, action: nil)
    let refreshButton = NSButton(title: "Check again", target: nil, action: nil)
    var checking = false
    var openingPackage = false

    static func main() {
        let app = NSApplication.shared
        let delegate = SetupApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        _ = delegate
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu()
        let item = NSMenuItem(); appMenu.addItem(item)
        let submenu = NSMenu(); item.submenu = submenu
        submenu.addItem(withTitle: "About Rollo USB Print Fix", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Quit Rollo USB Print Fix", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = appMenu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 610),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Rollo USB Print Fix"
        window.minSize = NSSize(width: 640, height: 580)
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "Rollo USB Print Fix")
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        let intro = NSTextField(wrappingLabelWithString: "Set up the printing fix for your USB-connected Rollo. Keep using your existing printer and the official Rollo driver.")
        headline.font = .systemFont(ofSize: 15, weight: .semibold)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        detail.isEditable = false
        detail.isSelectable = true
        detail.font = .systemFont(ofSize: 13)
        detail.textContainerInset = NSSize(width: 10, height: 10)
        detail.autoresizingMask = [.width]
        detail.isVerticallyResizable = true
        detail.isHorizontallyResizable = false
        detail.textContainer?.widthTracksTextView = true
        scroll.documentView = detail
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        refreshButton.target = self; refreshButton.action = #selector(refresh)
        installButton.target = self; installButton.action = #selector(install)
        removeButton.target = self; removeButton.action = #selector(remove)
        installButton.bezelStyle = .rounded; removeButton.bezelStyle = .rounded; refreshButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [refreshButton, progress, NSView(), removeButton, installButton])
        buttons.orientation = .horizontal; buttons.spacing = 10
        let guidance = NSTextField(wrappingLabelWithString: "Applies to all compatible USB Rollo printers listed above. Existing paper and darkness settings are kept. Labels may take about five seconds longer to print. Wi-Fi and AirPrint printers are not changed.")
        guidance.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, intro, headline, scroll, guidance, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -24),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 170),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            intro.widthAnchor.constraint(equalTo: stack.widthAnchor),
            headline.widthAnchor.constraint(equalTo: stack.widthAnchor),
            guidance.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidBecomeActive(_ notification: Notification) { if window != nil { refresh() } }

    @objc func refresh() {
        guard !checking && !openingPackage else { return }
        checking = true
        installButton.isEnabled = false; removeButton.isEnabled = false; refreshButton.isEnabled = false
        headline.stringValue = "Checking your printers…"; progress.startAnimation(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            let system = MacSystem()
            var text = ""
            var title = "Setup needs attention"
            var canInstall = false
            var canRemove = false
            do {
                if system.fm.fileExists(atPath: Paths.support + "/recovery.json") {
                    throw RepairError(16, "A previous setup was interrupted. Stop submitting labels and ask your administrator to run the recovery command in the included guide.")
                }
                let queues = try system.queues()
                let relevant = queues.filter { PPD.isRollo($0.ppd) || PPD.managed($0.ppd) }
                for queue in relevant {
                    let kind = PPD.managed(queue.ppd) ? "Fix enabled" : (PPD.supported(queue) ? "Compatible USB printer" : "Unsupported connection or driver")
                    text += "\(queue.name)\n\(kind) · \(queue.enabled ? "Enabled" : "Paused") · \(queue.jobs) pending jobs\n\n"
                }
                do {
                    let candidates = try Repair(system).candidates(removing: false)
                    canInstall = !candidates.isEmpty
                    title = "Ready to install on \(candidates.count) USB \(candidates.count == 1 ? "printer" : "printers")"
                    text += "Choose Install to continue with macOS Installer. You will need an administrator account.\n\nAfter setup, print one label from your usual app to check the result."
                } catch { text += String(describing: error) }
                canRemove = (try? Repair(system).candidates(removing: true).isEmpty) == false
                if !system.vendorAvailable() { title = "Install the official Rollo USB driver first" }
                if relevant.isEmpty { text = "No compatible Rollo printer was found.\n\n" + text }
            } catch { text = String(describing: error) }
            DispatchQueue.main.async {
                self.headline.stringValue = title
                self.detail.string = text
                self.installButton.isEnabled = canInstall; self.removeButton.isEnabled = canRemove
                self.refreshButton.isEnabled = true; self.progress.stopAnimation(nil); self.checking = false
            }
        }
    }

    @objc func install() { openPackage("Install") }
    @objc func remove() { openPackage("Remove") }
    func openPackage(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "pkg") else {
            let alert = NSAlert(); alert.messageText = "The installer package is missing"
            alert.informativeText = "Download or rebuild the complete setup app. No printer configuration was changed."
            alert.runModal(); return
        }
        let installURL: URL
        do {
            // Installer retains sessions by URL. A separate, immutable copy for
            // each attempt avoids reopening a failed/stale embedded-package session.
            let manager = FileManager.default
            let cache = try manager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let session = cache.appendingPathComponent("org.rollo-usb-pacing.setup/InstallerSessions")
                .appendingPathComponent(UUID().uuidString)
            try manager.createDirectory(at: session, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            installURL = session.appendingPathComponent(name + ".pkg")
            try Data(contentsOf: url).write(to: installURL, options: .withoutOverwriting)
            try manager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: installURL.path)
        } catch {
            let alert = NSAlert()
            alert.messageText = "The installer could not be prepared"
            alert.informativeText = "Check that your Mac has free disk space, then try again. No printer configuration was changed."
            alert.runModal(); return
        }
        openingPackage = true
        installButton.isEnabled = false; removeButton.isEnabled = false
        headline.stringValue = "Opening macOS Installer…"
        NSWorkspace.shared.open(installURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            DispatchQueue.main.async {
                self.openingPackage = false
                if error != nil {
                    let alert = NSAlert()
                    alert.messageText = "macOS Installer could not be opened"
                    alert.informativeText = "Try again, or open the standalone installer included with the download. No printer configuration was changed."
                    alert.runModal()
                }
                self.refresh()
            }
        }
    }
}
