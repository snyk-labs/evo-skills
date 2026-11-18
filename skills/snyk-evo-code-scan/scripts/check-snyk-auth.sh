#!/usr/bin/env sh
# Reports whether the Snyk CLI is authenticated, without printing any secret.
#
# Usage: check-snyk-auth.sh [path-to-snyk]   (defaults to `snyk` on PATH)
#
# Exit codes: 0 authenticated, 1 not authenticated / credentials rejected, 2 snyk not found.

set -u

snyk="${1:-snyk}"
if ! command -v "$snyk" >/dev/null 2>&1; then
  echo "snyk CLI not found ($snyk). Run install-snyk-cli.sh first." >&2
  exit 2
fi

if [ -n "${SNYK_TOKEN:-}" ]; then
  source_desc="SNYK_TOKEN environment variable"
elif [ -n "${SNYK_OAUTH_TOKEN:-}" ]; then
  source_desc="SNYK_OAUTH_TOKEN environment variable"
else
  source_desc="stored CLI config from snyk auth (if any)"
fi

if out="$("$snyk" whoami --experimental 2>&1)" && [ -n "$out" ]; then
  user="$(printf '%s\n' "$out" | tail -n1)"
  echo "authenticated: yes"
  echo "user: $user"
  echo "credential source: $source_desc"
  org="$("$snyk" config get org 2>/dev/null || true)"
  echo "configured org: ${org:-<none, the preferred org of the account is used>}"
  endpoint="$("$snyk" config get endpoint 2>/dev/null || true)"
  echo "api endpoint: ${SNYK_API:-${endpoint:-<default>}}"
  exit 0
fi

echo "authenticated: no"
echo "credential source tried: $source_desc"
reason="$(printf '%s\n' "$out" | grep -E 'ERROR|Status:' | sed 's/^ *//; s/ *$//' | paste -sd ';' -)"
[ -n "$reason" ] && echo "reason: $reason"
if [ -n "${SNYK_TOKEN:-}${SNYK_OAUTH_TOKEN:-}" ]; then
  echo "The credential was rejected. Check that it is valid, not expired, and for the right region (SNYK_API)."
fi
exit 1
