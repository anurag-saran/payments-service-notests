# payments-service-notests

Sibling of **[payments-service](https://github.com/anurag-saran/payments-service)** with
**no `*.java` under `src/test/java`**. Same app sources, DemoHttpServer, Dockerfile, and
deploy manifests — used to demo upgrade-delta's **REACHABILITY_ONLY** honesty path
(grade from call-site analysis; Surefire skipped).

Not a production payments product. Package: `com.example.payments`.

## Why a separate repo?

| | payments-service | payments-service-notests |
|---|---|---|
| Tests | Surefire + grades path | Empty `src/test/java` → REACHABILITY_ONLY |
| PipelineRun | `upgrade-delta-live-pr` | `upgrade-delta-live-pr-notests` |
| PVC | `upgrade-delta-live-reports` | `upgrade-delta-live-reports-notests` |
| Scorecard | Route `scorecard` | Route `scorecard-notests` |

Separate PVCs + viewers so concurrent demos never overwrite each other's reports.

## Build

JDK 17+.

```bash
mvn -B package
# Equivalent (kept for pipeline scripts):
mvn -B -Pci-community package
```

Produces a **fat / shaded** jar (dependencies packaged inside) and CycloneDX `target/bom.json`.
There are no unit/IT sources, so `verify` / Surefire is a no-op.

## Fast-lane demo (REACHABILITY_ONLY)

On `main`, remediable deps stay on **community** versions. Open a pom bump PR:

```bash
./scripts/demo-live-cycle.sh start
# …watch upgrade-delta-live-pr-notests-… on the cluster…
./scripts/demo-live-cycle.sh finish
```

Expect: grade + CAB path without selected Surefire tests. Scorecard URL uses the
**notests** route host (see `.tekton/pull-request-live.yaml`).

Details: upgrade-delta `docs/DEMO-LIVE-POM.md` § *Two live demos*.

## Layout

- `pom.xml` / `src/main/` — same call sites as payments-service
- `src/test/java/` — empty (`.gitkeep` only) on purpose
- `coverage-map.json` — retained for parity; unused when no test sources exist
- `.upgrade-delta/` — vendored upgrade-delta live pipeline
- `.tekton/pull-request-live.yaml` — PaC trigger (`app-name: payments-service-notests`)
