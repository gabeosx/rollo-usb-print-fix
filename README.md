# Rollo USB Print Fix

A macOS utility for USB Rollo printers that print incomplete labels. It keeps the official Rollo driver and adjusts how print data is sent to the printer.

## Requirements

- macOS 13 or newer, on Apple Silicon or Intel.
- A USB-connected Rollo printer using the official Rollo USB macOS driver.
- An administrator account for installation and removal.

Wi-Fi, AirPrint and remote/shared printer queues are not supported. Install the official driver from [Rollo's setup page](https://www.rollo.com/setup/) and add your printer in **System Settings → Printers & Scanners** before using this tool.

## Install

1. Download the Setup ZIP from [Releases](https://github.com/gabeosx/rollo-usb-print-fix/releases) and extract it.
2. Finish or cancel pending print jobs in **Print Center**.
3. Open **Rollo USB Print Fix**. It lists your compatible printers and any setup problems.
4. Choose **Install…** and follow macOS Installer. Authorize the installation when prompted.

The installer applies to all compatible USB Rollo printers on the Mac, including renamed printers. It keeps printer names, paper, speed and darkness settings, and selects 203 dpi when available. Printers that were paused remain paused. No jobs are canceled and no labels are printed during setup.

## Print

Keep choosing your existing Rollo printer in your usual app. For standard shipping labels, use:

- **Paper:** 4×6 inches
- **Orientation:** portrait
- **Scale:** 100%
- **Resolution:** 203 dpi
- **Preset:** Default Settings, or a saved preset using those settings

Resume a paused printer in Print Center when ready. Print one label to check the result before sending a batch. A typical 4×6 label takes about five additional seconds to transfer.

The fix works locally with the existing print queue. It requires no account, background service or external data upload.

## Remove

Finish or cancel pending jobs, open **Rollo USB Print Fix**, and choose **Remove…**. The standalone removal package does the same thing.

Removal restores the original Rollo converter and keeps the official driver installed. Current paper, speed and darkness settings are preserved. The earlier default resolution is restored if it has not since been changed. The management tool and local backups remain available for recovery.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| No compatible printer found | Install the official USB driver, connect by USB, and add the printer in Printers & Scanners. |
| Setup reports pending jobs | Finish or cancel them in Print Center, then choose Check again. |
| Label is tiny, cropped or misaligned | Check paper size, orientation, scaling and the saved preset in the printing app. |
| Printer remains paused after interrupted setup | Stop sending labels and ask an administrator to follow the [recovery guide](docs/ADMINISTRATORS.md#recover-interrupted-setup). |
| Printer or driver was reinstalled | Open this tool and install the fix again if needed. |

The fix changes USB print delivery. Mechanical feeding problems, label-stock calibration and incorrect document layout need separate attention.

## Administrators and contributors

- [Deployment, selected printers, removal and recovery](docs/ADMINISTRATORS.md)
- [Build from source](docs/DEVELOPMENT.md)
- [Signing and release packaging](docs/RELEASE.md)
- [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [License](LICENSE)

An independent utility, not an official Rollo product. The official driver is a separate prerequisite; no vendor driver binaries or PPDs are distributed here.
