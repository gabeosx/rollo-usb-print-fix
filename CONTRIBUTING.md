# Contributing

Use synthetic labels and preserve user privacy. This project deliberately excludes vendor binaries/PPDs, copied USB-backend source, real label PDFs and raw printer data.

Before submitting a change:

```sh
./build.sh
python3 Tests/test_filter.py
python3 audit.py
python3 verify_distribution.py
```

The installer tests use synthetic queues and never print. The filter tests compile a synthetic converter in a temporary directory; they do not invoke the official Rollo converter. Distribution verification expands packages without installing them. Read-only `build/rollo-pacing status` and `preflight install` inspect local queues, so review their output before sharing queue names.

Changes to the root-running installer, queue state transitions, rollback and recovery need tests for failure paths. Keep runtime components native and offline. Preserve the official converter and unrelated queues. Do not add automatic test printing, job cancellation, telemetry or background queue watchers without a separately reviewed design.

For hardware reports, describe:

- Rollo model, USB connection/hub, driver and macOS versions, and Mac architecture.
- App/browser, paper size, resolution, scale, and whether a saved preset was used.
- Whether the queue used pacing, and whether the physical label was full, aligned, readable and fed normally.
- Whether the job was one label, multiple copies or a multi-page batch.
- Installation/removal/recovery result and a sanitized error description.

Do not attach shipping labels, customer information, serial numbers, signed URLs, full logs, recovery backups or raw printer output. A successful software job alone is not physical validation. Follow the release qualification checklist when adding support for more configurations.
