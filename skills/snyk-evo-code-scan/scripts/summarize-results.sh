#!/usr/bin/env sh
# Decides what a `snyk rift test --experimental` run actually produced, without trusting the exit code.
#
# Usage: summarize-results.sh <results.json> [cli-exit-code]
#
# `rift test` exits 0 whether or not it found anything, so the exit code only tells you the scan
# ran. The JSON results file is the source of truth: `{"findings":[...]}`, empty when clean.
#
# Prints a line `scan outcome: findings|clean|failed`, then counts and one line per finding.
# Exit codes: 0 the scan completed (findings or clean), 1 the scan did not complete or the results
# are unusable (do not report "no issues"), 2 bad usage.
#
# Uses jq or python3 when available and falls back to grep/awk, which lists severity and title only.

set -u

results="${1:-}"
cli_rc="${2:-}"

if [ -z "$results" ]; then
  echo "usage: summarize-results.sh <results.json> [cli-exit-code]" >&2
  exit 2
fi

fail() {
  echo "scan outcome: failed"
  echo "reason: $1"
  echo "Do not report this as 'no issues found'. Read the console output, fix the cause (see Troubleshooting in SKILL.md), and re-run."
  exit 1
}

case "$cli_rc" in
  ''|0|1) ;;
  2) fail "snyk exited with code 2 (the scan failed)" ;;
  3) fail "snyk exited with code 3 (nothing supported to scan here)" ;;
  *) fail "snyk exited with unexpected code $cli_rc" ;;
esac

[ -f "$results" ] || fail "results file not found: $results (the scan wrote no results)"
[ -s "$results" ] || fail "results file is empty: $results"

# Emits one "severity<TAB>title<TAB>location" line per finding, or exits 3 if the file is not a results document.
extract_jq() {
  jq -e '.findings | type == "array"' "$results" >/dev/null 2>&1 || return 3
  jq -r '.findings[] | [
      ((.severity // "unknown") | ascii_downcase),
      ((.title // "untitled") | gsub("[\t\n]"; " ")),
      ((.locations // [])[0] | if . then "\(.file_path // ""):\(.from_line // "")" else "" end)
    ] | @tsv' "$results"
}

extract_python() {
  python3 - "$results" <<'EOF'
import json, sys
try:
    findings = json.load(open(sys.argv[1]))["findings"]
    assert isinstance(findings, list)
except Exception:
    sys.exit(3)
for f in findings:
    locs = f.get("locations") or [{}]
    loc = locs[0].get("file_path", "")
    if loc and locs[0].get("from_line") is not None:
        loc += ":%s" % locs[0]["from_line"]
    title = str(f.get("title") or "untitled").replace("\t", " ").replace("\n", " ")
    print("%s\t%s\t%s" % (str(f.get("severity") or "unknown").lower(), title, loc))
EOF
}

extract_grep() {
  grep -q '"findings"' "$results" || return 3
  grep -o '"\(title\|severity\)": *"\([^"\\]\|\\.\)*"' "$results" | awk '
    {
      key = $0; sub(/^"/, "", key); sub(/".*/, "", key)
      val = $0; sub(/^"[a-z]*": *"/, "", val); sub(/"$/, "", val)
      if (key == "title") t = val; else s = tolower(val)
      if (t != "" && s != "") { printf "%s\t%s\t\n", s, t; t = ""; s = "" }
    }'
}

if command -v jq >/dev/null 2>&1; then
  extractor=extract_jq
elif command -v python3 >/dev/null 2>&1; then
  extractor=extract_python
else
  extractor=extract_grep
fi

rows="$($extractor)"
[ $? -eq 0 ] || fail "results file is not a valid results document (expected {\"findings\":[...]}): $results"

if [ -z "$rows" ]; then
  echo "scan outcome: clean"
  echo "findings: 0"
  [ "$cli_rc" = "1" ] && echo "note: snyk exited 1 but the results contain no findings; trusting the results file."
  exit 0
fi

total="$(printf '%s\n' "$rows" | wc -l | tr -d ' ')"
echo "scan outcome: findings"
echo "findings: $total"
printf '%s\n' "$rows" | awk -F '\t' '
  { n[$1]++ }
  END {
    split("critical high medium low", order, " ")
    out = ""
    for (i = 1; i <= 4; i++) if (order[i] in n) { out = out (out ? ", " : "") order[i] "=" n[order[i]]; delete n[order[i]] }
    for (k in n) out = out (out ? ", " : "") k "=" n[k]
    print "by severity: " out
  }'
echo "details (most severe first):"
printf '%s\n' "$rows" | awk -F '\t' '
  BEGIN { rank["critical"] = 1; rank["high"] = 2; rank["medium"] = 3; rank["low"] = 4 }
  { r = ($1 in rank) ? rank[$1] : 9; printf "%d\t%s\n", r, $0 }' | sort -t "$(printf '\t')" -k1,1n | cut -f2- | awk -F '\t' '
  { printf "- [%s] %s%s\n", $1, $2, ($3 != "" ? " (" $3 ")" : "") }'
[ "$cli_rc" = "0" ] && echo "note: snyk exited 0 even though findings exist; that is normal for rift test."
exit 0
