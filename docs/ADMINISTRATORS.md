# Administrator guide

Use this guide to deploy to selected printers, inspect configuration, remove the fix or recover interrupted setup. Installation requires an administrator; printing afterward does not. Validate your actual printer models, applications and label batches before a fleet rollout.

## Inspect before changing anything

The installed management tool is:

```sh
'/Library/Application Support/Rollo USB Pacing/rollo-pacing' status
'/Library/Application Support/Rollo USB Pacing/rollo-pacing' preflight install
```

These commands are read-only. They show queue names, pacing state, queue states, pending-job counts and default resolution. They do not show device serials, document names, addresses or job payloads. Queue names may still contain organization-specific information; review output before sharing it.

Before the first installation, use `build/rollo-pacing` from a local build instead of the installed path. No tool is downloaded or executed from the network by the package.

## Installation and selection

The setup app provides read-only discovery and actionable errors before opening Installer. The graphical package targets **every supported USB Rollo queue**. The package itself checks for the driver and interrupted recovery record in its welcome stage; the privileged script rechecks all compatibility and job conditions. Its preinstall stage blocks incoming jobs and checks for jobs again before pausing idle queues or replacing any executable. It refuses pending or held jobs and never cancels them. Postinstall changes the routing and restores each queue's prior enabled and accepting states. If Installer crashes between stages, run recovery before retrying.

For managed deployment, install a **signed and notarized, qualified** package on the running OS:

```sh
sudo /usr/sbin/installer -pkg Rollo-USB-Print-Fix-VERSION-signed.pkg -target /
```

For selected queues, stage the two signed universal binaries with your management system, root-owned and mode 755, at these exact locations:

- `build/rollo-pacing` → `/Library/Application Support/Rollo USB Pacing/rollo-pacing`
- `build/rastertorollo-paced` → `/Library/Printers/RolloPacing/rastertorollo-paced`

Then run:

```sh
sudo '/Library/Application Support/Rollo USB Pacing/rollo-pacing' install --queue Shipping_Station_A
```

Repeat `--queue NAME` to select several queues. Omitting it applies to all compatible queues. Do not run an unqualified unsigned preview fleet-wide. No watcher automatically changes queues added later.

Installation changes the selected queue's filter reference and, when available, default resolution to 203 dpi. Other defaults and the printer destination are retained. Application presets can override resolution; distribute a 203 dpi preset through your existing print configuration process if required. Paper size is not forced to 4×6 because deployed printers can use other stock.

## Verify

1. Run `status` and check that the expected queues say `PACING ENABLED`.
2. If a queue was previously paused or rejecting jobs, resume/accept it through your normal administrative process when appropriate. Setup intentionally preserves these states.
3. Print one synthetic label through the actual application. Inspect full content, alignment, darkness, feed and barcode readability.
4. Test the required single-label, multi-page, copies and concurrent-user workloads before deployment.

Unrelated Wi-Fi/AirPrint/non-Rollo queues are not candidates. The converter must exist at the official supported path and have root ownership with safe file/parent permissions. Unknown filter chains are excluded. The local CUPS socket is used explicitly; shell interpolation and user-configured remote CUPS servers are not used.

## Roll back

Use the **Remove Rollo USB Pacing** package, or:

```sh
sudo '/Library/Application Support/Rollo USB Pacing/rollo-pacing' uninstall
```

For selected queues:

```sh
sudo '/Library/Application Support/Rollo USB Pacing/rollo-pacing' uninstall --queue Shipping_Station_A
```

The queue's current PPD is patched back to the vendor converter, preserving later settings. The original default resolution is restored only if the repair changed it, the device identity still matches, and the current default remains 203 dpi. A vendor reinstall may already have removed the routing; an uninstall with no managed queues succeeds without modifying them. The standalone uninstaller can run even if the management tool is not installed, using its own embedded tool.

The pacing binary is removed after an all-queue uninstall only if no installed PPD still references it. Selected-queue uninstall retains it for other queues. Management binaries, root-readable records and backups remain; there is no background service. Installed package receipts are retained by macOS.

## Recover interrupted setup

Use this when setup reports an interrupted transaction, a failure leaves queues paused, or the installer was terminated after preinstall. First stop submitting new jobs and finish/cancel pending jobs in Print Center. Then:

```sh
sudo '/Library/Application Support/Rollo USB Pacing/rollo-pacing' recover
```

If the installation stopped before copying that tool, build this version from source and run:

```sh
sudo ./build/rollo-pacing recover
```

Recovery uses the durable pre-operation snapshot and restores queue routing, resolution and enabled/accepting states. It does not delete jobs. If a queue was removed, its device changed, or another administrator edited its PPD during the operation, automated recovery refuses to overwrite that change. Reconcile the configuration manually from the root-readable backup, then retry recovery. Never copy an entire old PPD over a newer driver without reviewing it.

Files:

- `/Library/Application Support/Rollo USB Pacing/recovery.json`: active interrupted-transaction record, present only until success/recovery.
- `/Library/Application Support/Rollo USB Pacing/Backups/`: per-operation local recovery snapshots, mode 600; directory mode 700.
- `/Library/Application Support/Rollo USB Pacing/state.json`: per-queue resolution restoration records, mode 600, with hashed device identity.
- `/Library/Application Support/Rollo USB Pacing/setup.lock`: advisory lock preventing simultaneous management operations. A crashed process releases the lock automatically.

These files include locally installed PPDs and queue names. They are not public support bundles and must not be committed or redistributed. Recovery backups are retained deliberately; follow your organization's retention policy.

## Exit codes

| Code | Meaning / next step |
| --- | --- |
| 0 | Success, or a successful no-op uninstall |
| 1 | Unexpected file/process error; review the local Installer log |
| 2 | Invalid command arguments |
| 10 | Official converter missing or unsafe; install/repair the official driver |
| 11 | No matching supported queue / invalid selected queue |
| 12 | Pending or newly arriving jobs; clear normally and retry |
| 13 | Conflicting setup, changed queue, unsafe permissions or missing payload |
| 14 | Printing-service command or verification failed |
| 15 | Administrator privileges required |
| 16 | Interrupted setup, recovery conflict or incomplete rollback; inspect recovery data |

`prepare-install` and `commit-install` are internal package stages, not normal deployment commands. They use the same transaction engine as the public `install` command.
