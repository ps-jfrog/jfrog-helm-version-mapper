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
