# Security and private data

This project installs a printer filter and changes local CUPS queue settings with administrator authorization. It does not install a daemon, network listener, telemetry, browser extension or account integration. Print bytes pass through unchanged to the existing driver/backend path.

Do not attach shipping labels, printer output streams, full CUPS logs, signed document URLs, credentials, serial numbers or recovery backups to public issues. The read-only `status` output omits document payloads, device URLs and serials, but queue names can still identify a location or organization. Review it before sharing.

The new filter is installed root-owned, mode 755. Management uses fixed system executables with argument arrays and a local CUPS socket, checks file and parent ownership/permissions, refuses symlinked state files, uses a root-owned lock, and records recovery data before changing queues. It blocks incoming jobs and refuses pending jobs rather than deleting them. A conflicting administrator change or incomplete rollback is an error requiring review.

The original vendor converter is an external prerequisite and remains a separate trusted component. This workaround does not audit or sandbox that converter. No runtime binaries or PPDs from the vendor or Apple are included.

Report vulnerabilities through [GitHub private vulnerability reporting](https://github.com/gabeosx/rollo-usb-print-fix/security/advisories/new). Keep exploit details and private artifacts out of public issues.
