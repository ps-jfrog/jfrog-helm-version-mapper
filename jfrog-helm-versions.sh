#!/usr/bin/env bash
# =============================================================================
# jfrog-helm-versions.sh
# Quickly maps JFrog Helm chart versions to their actual product (appVersion)
# versions — the ones that appear in JFrog release notes.
#
# Pulls live data from https://charts.jfrog.io/index.yaml
# No local Helm client or `helm repo add` required.
#
# USAGE
#   ./jfrog-helm-versions.sh                           # latest of every chart
#   ./jfrog-helm-versions.sh artifactory               # latest for one chart
#   ./jfrog-helm-versions.sh artifactory --all         # all versions for a chart
#   ./jfrog-helm-versions.sh artifactory --chart 107.133.23   # exact lookup by chart ver
#   ./jfrog-helm-versions.sh artifactory --app 7.133.23       # lookup by appVersion
#   ./jfrog-helm-versions.sh --all                     # all versions, every chart
#   ./jfrog-helm-versions.sh --json                    # JSON output (latest only)
#   ./jfrog-helm-versions.sh artifactory --all --json  # all versions for chart, JSON
#   ./jfrog-helm-versions.sh --list                    # list all chart names in index
#   ./jfrog-helm-versions.sh --refresh                 # force re-download of index
#
# VERSIONING SCHEME (for reference)
#   Artifactory chart:  107.X.Y  →  appVersion 7.X.Y
#   Xray chart:         103.X.Y  →  appVersion 3.X.Y
#   Distribution chart: 102.X.Y  →  appVersion 2.X.Y
#   jfrog-platform:     11.X.Y   →  appVersion = Artifactory version bundled
#
# DEPENDENCIES: curl, python3 (stdlib only — no pyyaml needed)
# =============================================================================

set -euo pipefail

INDEX_URL="https://charts.jfrog.io/index.yaml"
CACHE_FILE="${TMPDIR:-/tmp}/jfrog-helm-index.yaml"
CACHE_TTL=3600   # seconds before re-downloading

# ── Colour output (disabled when not a TTY) ───────────────────────────────────
if [[ -t 1 ]]; then
  BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
  YELLOW='\033[1;33m'; RESET='\033[0m'; DIM='\033[2m'; RED='\033[0;31m'
else
  BOLD=''; CYAN=''; GREEN=''; YELLOW=''; RESET=''; DIM=''; RED=''
fi

die()  { echo -e "${RED}ERROR:${RESET} $*" >&2; exit 1; }
info() { echo -e "${CYAN}→${RESET} $*" >&2; }

need_cmd() { command -v "$1" &>/dev/null || die "'$1' not found — please install it."; }

# ── Fetch / cache the Helm chart index ───────────────────────────────────────
refresh_index() {
  local tmp_file
  tmp_file=$(mktemp "${CACHE_FILE}.XXXXXX") \
    || die "Failed to create temp file for index download."
  info "Downloading chart index from ${INDEX_URL} …"
  if ! curl -sSfL --connect-timeout 15 --max-time 90 \
            -o "${tmp_file}" "${INDEX_URL}"; then
    rm -f "${tmp_file}"
    die "Failed to download index.yaml. Check network/proxy settings."
  fi
  if ! mv "${tmp_file}" "${CACHE_FILE}"; then
    rm -f "${tmp_file}"
    die "Failed to move downloaded index into place at ${CACHE_FILE}."
  fi
  info "Index cached at ${CACHE_FILE} ($(wc -l < "${CACHE_FILE}") lines)"
}

ensure_index() {
  local force="${1:-0}"
  if [[ "${force}" == "1" ]]; then
    refresh_index
  elif [[ ! -f "${CACHE_FILE}" ]]; then
    refresh_index
  else
    local file_time now age
    file_time=$(date -r "${CACHE_FILE}" +%s 2>/dev/null || echo 0)
    now=$(date +%s)
    age=$(( now - file_time ))
    if [[ ${age} -gt ${CACHE_TTL} ]]; then
      info "Cache is ${age}s old (TTL ${CACHE_TTL}s), refreshing …"
      refresh_index
    else
      info "Using cached index (${age}s old). Use --refresh to force update."
    fi
  fi
}

# ── Pure-Python index.yaml parser ─────────────────────────────────────────────
# index.yaml structure (4-space indent for chart entry fields):
#   entries:
#     artifactory:
#     - apiVersion: v2
#       created: 2026-06-29T...
#       ...
#       dependencies:
#       - name: postgresql
#         version: 16.7.26      ← 6-space: dep version, NOT the chart version
#       appVersion: "7.146.22"  ← 4-space: product version
#       version: "107.146.22"   ← 4-space: chart version
#     - ...
#
# We extract appVersion + version + created for each entry belonging to target_chart.

PARSER_SCRIPT=$(cat << 'PYEOF'
import sys, re

index_file = sys.argv[1]
target_chart = sys.argv[2]
mode = sys.argv[3]   # "latest" | "all"

results = []
in_entries = False
in_target = False
current = None

with open(index_file, 'r', encoding='utf-8') as fh:
    for raw in fh:
        line = raw.rstrip('\n')

        # Top-level entries: block
        if line == 'entries:':
            in_entries = True
            continue
        if not in_entries:
            continue

        # Leaving entries block (non-indented non-empty line)
        if line and not line[0].isspace():
            break

        # Chart name key at exactly 2-space indent
        m = re.match(r'^  ([a-zA-Z0-9_-]+):\s*$', line)
        if m:
            if in_target and current is not None:
                results.append(dict(current))
                current = None
            in_target = (m.group(1) == target_chart)
            continue

        if not in_target:
            continue

        # New list item: "  - " (2 spaces + dash + space)
        if re.match(r'^  - ', line):
            if current is not None:
                results.append(dict(current))
            current = {}
            continue

        # Key-value at exactly 4-space indent (chart-level fields)
        # Important: dependencies sub-fields are at 6-space — we skip them
        if current is not None:
            m = re.match(r'^    (appVersion|version|created):\s*"?([^"\n]+?)"?\s*$', line)
            if m:
                current[m.group(1)] = m.group(2)

# Flush last entry
if in_target and current is not None:
    results.append(current)

if not results:
    print(f"NOTFOUND:{target_chart}")
    sys.exit(0)

# Keep only entries that have a version field
results = [r for r in results if 'version' in r]

def ver_key(r):
    try:
        return tuple(int(x) for x in r['version'].split('.'))
    except Exception:
        return (0,)

results.sort(key=ver_key, reverse=True)

if mode == 'latest':
    results = results[:1]

for r in results:
    v   = r.get('version',    'unknown')
    av  = r.get('appVersion', 'unknown')
    dt  = r.get('created',    '')[:10]
    print(f"{v}\t{av}\t{dt}")
PYEOF
)

parse_chart_versions() {
  python3 - "${CACHE_FILE}" "$1" "$2" <<< "${PARSER_SCRIPT}"
}

# ── List all chart names from the index ──────────────────────────────────────
list_charts() {
  python3 - "${CACHE_FILE}" << 'PYEOF'
import sys, re
in_entries = False
charts = []
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    for line in fh:
        line = line.rstrip('\n')
        if line == 'entries:':
            in_entries = True
            continue
        if not in_entries:
            continue
        if line and not line[0].isspace():
            break
        m = re.match(r'^  ([a-zA-Z0-9_-]+):\s*$', line)
        if m:
            charts.append(m.group(1))
print('\n'.join(sorted(charts)))
PYEOF
}

# ── Display helpers ───────────────────────────────────────────────────────────
print_header() {
  printf "${BOLD}%-26s  %-16s  %-14s  %s${RESET}\n" \
    "CHART" "CHART VERSION" "APP VERSION" "RELEASED"
  printf '%s\n' "$(python3 -c "print('─'*72)")"
}

print_row() {
  printf "${BOLD}%-26s${RESET}  ${CYAN}%-16s${RESET}  ${GREEN}%-14s${RESET}  ${DIM}%s${RESET}\n" \
    "$1" "$2" "$3" "$4"
}

_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "${s}"
}

json_row() {
  printf '  {"chart":"%s","chartVersion":"%s","appVersion":"%s","released":"%s"}' \
    "$(_json_escape "$1")" "$(_json_escape "$2")" \
    "$(_json_escape "$3")" "$(_json_escape "$4")"
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  need_cmd curl
  need_cmd python3

  local target_chart=""
  local show_all=0
  local lookup_chart_ver=""
  local lookup_app_ver=""
  local json_out=0
  local force_refresh=0
  local do_list=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --refresh)  force_refresh=1;  shift ;;
      --all)      show_all=1;       shift ;;
      --json)     json_out=1;       shift ;;
      --list)     do_list=1;        shift ;;
      --chart)    [[ $# -ge 2 ]] || die "--chart requires a version argument"
                  lookup_chart_ver="$2"; shift 2 ;;
      --app)      [[ $# -ge 2 ]] || die "--app requires a version argument"
                  lookup_app_ver="$2"; shift 2 ;;
      --help|-h)
        grep '^#' "$0" 2>/dev/null | head -35 | sed 's/^# \{0,2\}//' || true
        exit 0 ;;
      -*)  die "Unknown option: $1 (try --help)" ;;
      *)   target_chart="$1"; shift ;;
    esac
  done

  ensure_index "${force_refresh}"

  # --list: just print chart names and exit
  if [[ "${do_list}" == "1" ]]; then
    echo "Charts available in charts.jfrog.io:"
    list_charts | sed 's/^/  /'
    exit 0
  fi

  # Build chart list to query
  local charts=()
  if [[ -n "${target_chart}" ]]; then
    charts=("${target_chart}")
  else
    while IFS= read -r _c; do charts+=("${_c}"); done < <(list_charts)
  fi

  local mode="latest"
  [[ "${show_all}" == "1" ]] && mode="all"

  # ── Exact version lookups ─────────────────────────────────────────────────
  if [[ -n "${lookup_chart_ver}" || -n "${lookup_app_ver}" ]]; then
    [[ ${#charts[@]} -eq 0 ]] && die "Specify a chart name when using --chart or --app."
    local ch="${charts[0]}"
    local rows
    rows=$(parse_chart_versions "${ch}" "all")
    if [[ "${rows}" == NOTFOUND:* ]]; then
      die "Chart '${ch}' not found. Run --list for valid names."
    fi
    [[ "${json_out}" == "0" ]] && print_header
    local json_items=()
    while IFS=$'\t' read -r cv av dt; do
      local match=0
      [[ -n "${lookup_chart_ver}" && "${cv}" == "${lookup_chart_ver}" ]] && match=1
      [[ -n "${lookup_app_ver}"   && "${av}" == "${lookup_app_ver}"   ]] && match=1
      if [[ "${match}" == "1" ]]; then
        if [[ "${json_out}" == "0" ]]; then
          print_row "${ch}" "${cv}" "${av}" "${dt}"
        else
          json_items+=("$(json_row "${ch}" "${cv}" "${av}" "${dt}")")
        fi
      fi
    done <<< "${rows}"
    if [[ "${json_out}" == "1" ]]; then
      echo "["
      local last=$(( ${#json_items[@]} - 1 ))
      for i in "${!json_items[@]}"; do
        [[ $i -lt $last ]] && echo "${json_items[$i]}," || echo "${json_items[$i]}"
      done
      echo "]"
    fi
    return
  fi

  # ── Normal table / JSON output ────────────────────────────────────────────
  local json_items=()
  [[ "${json_out}" == "0" ]] && print_header

  for chart in "${charts[@]}"; do
    local rows
    rows=$(parse_chart_versions "${chart}" "${mode}")
    if [[ "${rows}" == NOTFOUND:* ]]; then
      [[ "${json_out}" == "0" ]] && \
        printf "  ${YELLOW}%-26s  (not found in index)${RESET}\n" "${chart}"
      continue
    fi
    while IFS=$'\t' read -r cv av dt; do
      if [[ "${json_out}" == "0" ]]; then
        print_row "${chart}" "${cv}" "${av}" "${dt}"
      else
        json_items+=("$(json_row "${chart}" "${cv}" "${av}" "${dt}")")
      fi
    done <<< "${rows}"
  done

  if [[ "${json_out}" == "1" ]]; then
    echo "["
    local last=$(( ${#json_items[@]} - 1 ))
    for i in "${!json_items[@]}"; do
      [[ $i -lt $last ]] && echo "${json_items[$i]}," || echo "${json_items[$i]}"
    done
    echo "]"
  else
    echo ""
    echo -e "${DIM}Tip: appVersion = the JFrog product version used in release notes."
    echo -e "     Use --all for full history, --json for CI/scripting output."
    echo -e "     Source: ${INDEX_URL}${RESET}"
  fi
}

main "$@"
