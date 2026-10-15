# Build and development

## Build requirements

Use macOS with Xcode Command Line Tools. Python 3 is needed for the optional filter tests and distribution audits, not by the installed utility.

```sh
./build.sh
```

This runs the transaction and Installer JavaScript tests, builds universal arm64/x86_64 executables targeting macOS 13+, and creates a setup app plus standalone install/removal packages in `dist/`. Without publisher signing identities, outputs are labeled unsigned previews and executables receive ad-hoc signatures. End users do not need Xcode, Python or another runtime.

The Codex Run action invokes `script/build_and_run.sh` to build and launch the setup app. It supports `--verify`, `--debug`, `--logs` and `--telemetry`.

## Test and inspect

```sh
python3 Tests/test_filter.py
python3 audit.py
python3 verify_distribution.py
./build/rollo-pacing status
./build/rollo-pacing preflight install
```

Transaction tests use synthetic PPDs and a fake printing system. Filter tests compile a synthetic converter. Package audits expand artifacts without installing them. None of those tests prints or changes a real queue. The last two commands inspect local queues without modifying them; review queue names before sharing output.

## Components

- `Sources/filter.c`: CUPS filter that launches the installed vendor converter with unchanged arguments/input and forwards its output in writes of at most 512 bytes, separated by 20 ms. A read-only side-channel request waits for backend readiness. Errors and cancellation propagate to CUPS.
- `Sources/Repair.swift`: queue discovery, settings transformation, transaction/recovery storage and local CUPS administration.
- `Sources/main.swift`: privileged management commands used by packages and administrators.
- `Sources/Assistant.swift`: unprivileged AppKit setup window. It inspects printers and opens bundled packages; it does not perform privileged changes.
- `Packaging/`: standard macOS Installer product definitions, pages and scripts. Installer JavaScript uses built-in file checks; it does not execute external setup-check programs.

Preinstall blocks incoming jobs, checks again for arriving jobs, pauses only idle queues and records a durable recovery snapshot before any executable is replaced. Postinstall changes the routing, verifies it, saves restoration records and restores earlier queue states. Failure attempts rollback; conflicting administrator changes or active jobs prevent unsafe rollback and retain recovery data.

Do not add vendor executables, PPDs, customer labels, print streams, machine logs or signing credentials to the repository. The original converter and macOS libraries remain external dependencies.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for change validation and [RELEASE.md](RELEASE.md) for signing and distribution.
