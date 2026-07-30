# jfrog-helm-version-mapper

A single Bash script that maps **JFrog Helm chart versions** to their corresponding **product (appVersion) versions** — the ones that appear in JFrog release notes — without requiring a local Helm client or `helm repo add`.

Data is pulled live from [`https://charts.jfrog.io/index.yaml`](https://charts.jfrog.io/index.yaml) and cached locally for one hour.

## Dependencies

| Tool | Notes |
|------|-------|
| `curl` | Fetches the chart index |
| `python3` | Parses YAML; uses stdlib only — no `pyyaml` required |

## Usage

```bash
chmod +x jfrog-helm-versions.sh

# Latest chart → appVersion for every chart
./jfrog-helm-versions.sh

# Latest for a specific chart
./jfrog-helm-versions.sh artifactory

# All historical versions for a chart
./jfrog-helm-versions.sh artifactory --all

# Exact lookup by chart version
./jfrog-helm-versions.sh artifactory --chart 107.133.23

# Exact lookup by appVersion (product version)
./jfrog-helm-versions.sh artifactory --app 7.133.23

# All versions for every chart
./jfrog-helm-versions.sh --all

# JSON output (latest only — suitable for CI/scripting)
./jfrog-helm-versions.sh --json

# All versions for a chart, JSON output
./jfrog-helm-versions.sh artifactory --all --json

# List all chart names available in the index
./jfrog-helm-versions.sh --list

# Force re-download of the cached index
./jfrog-helm-versions.sh --refresh
```

## Dependency Lookup (`--dep`)

The `jfrog-platform` umbrella chart bundles Artifactory, Xray, Distribution, and others. Its
`appVersion` only tracks the **Artifactory** version, so `--app` cannot find it by Xray version.
Use `--dep` to look up the platform chart by any bundled sub-chart version:

```bash
# Find the jfrog-platform chart that bundles Xray 3.143.34 (product version)
./jfrog-helm-versions.sh jfrog-platform --dep xray=3.143.34

# Chart version prefix also works
./jfrog-helm-versions.sh jfrog-platform --dep xray=103.143.34

# All historical platform releases that bundled that Xray version
./jfrog-helm-versions.sh jfrog-platform --dep xray=3.143.34 --all

# JSON output for CI/scripting
./jfrog-helm-versions.sh jfrog-platform --dep xray=3.143.34 --json

# Works for any bundled sub-chart (artifactory, distribution, catalog, worker, …)
./jfrog-helm-versions.sh jfrog-platform --dep distribution=2.52.2
```

### `--dep` output

```
CHART          CHART VERSION   APP VERSION    RELEASED      DEP     DEP VERSION
──────────────────────────────────────────────────────────────────────────────────
jfrog-platform 11.5.13         7.146.34       2026-07-29    xray    103.143.34
```

### `--dep --json` output

```json
[
  {"chart":"jfrog-platform","chartVersion":"11.5.13","appVersion":"7.146.34","released":"2026-07-29","depName":"xray","depVersion":"103.143.34"}
]
```

## Versioning Scheme

JFrog's Helm charts encode a prefix in the chart version that corresponds to the product:

| Chart | Chart version prefix | appVersion (product version) |
|-------|---------------------|------------------------------|
| `artifactory` | `107.X.Y` | `7.X.Y` |
| `xray` | `103.X.Y` | `3.X.Y` |
| `distribution` | `102.X.Y` | `2.X.Y` |
| `jfrog-platform` | `11.X.Y` | Artifactory version bundled |

## Output

### Table (default)

```
CHART                       CHART VERSION     APP VERSION     RELEASED
────────────────────────────────────────────────────────────────────────
artifactory                 107.146.22        7.146.22        2026-06-25
xray                        103.146.5         3.146.5         2026-06-24
...
```

### JSON (`--json`)

```json
[
  {"chart":"artifactory","chartVersion":"107.146.22","appVersion":"7.146.22","released":"2026-06-25"},
  ...
]
```

## Caching

The index is cached at `$TMPDIR/jfrog-helm-index.yaml` (typically `/tmp/jfrog-helm-index.yaml`) with a **1-hour TTL**. Use `--refresh` to force an immediate re-download.

## License

MIT
