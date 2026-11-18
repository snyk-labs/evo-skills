#!/usr/bin/env sh
# Runs inside a fresh container as a non-root user with no Snyk CLI.
# Exercises the snyk-evo-code-scan skill scripts the way an agent would.
#
# Expects the skill mounted at /skill and the fixture project at /fixture.
# If SNYK_TOKEN is set, also performs a real authenticated scan.

set -u

SKILL=/skill
pass=0
fail=0
skip=0

ok()   { pass=$((pass + 1)); printf '  PASS  %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /'; }
skp()  { skip=$((skip + 1)); printf '  SKIP  %s\n' "$1"; }

real_token="${SNYK_TOKEN:-}"
unset SNYK_TOKEN

# shellcheck disable=SC1091
echo "== Environment: $(. /etc/os-release && echo "$PRETTY_NAME") / $(uname -m) / user $(id -un)"

# 1. Fresh machine: no snyk anywhere.
if command -v snyk >/dev/null 2>&1; then
  bad "snyk is not preinstalled" "found $(command -v snyk)"
else
  ok "snyk is not preinstalled"
fi

# 2. Install via the skill script.
out="$(sh "$SKILL/scripts/install-snyk-cli.sh" 2>/tmp/install.err)"
rc=$?
SNYK_BIN="$(printf '%s\n' "$out" | tail -n1)"
if [ $rc -eq 0 ] && [ -x "$SNYK_BIN" ]; then
  ok "install-snyk-cli.sh installed $("$SNYK_BIN" --version) at $SNYK_BIN"
else
  bad "install-snyk-cli.sh succeeds" "$(cat /tmp/install.err)"
  echo "== Cannot continue without a CLI. pass=$pass fail=$fail skip=$skip"
  exit 1
fi
if grep -q 'checksum verified' /tmp/install.err; then ok "download checksum verified"; else bad "download checksum verified" "$(cat /tmp/install.err)"; fi

# 3. rift test is available and flags are present.
help="$("$SNYK_BIN" rift test --help 2>&1)"
if printf '%s' "$help" | grep -q -- '--experimental' && printf '%s' "$help" | grep -q -- '--json-file-output'; then
  ok "'snyk rift test --help' lists --experimental and --json-file-output"
else
  bad "'snyk rift test --help' lists expected flags" "$help"
fi

# 4. Re-running the installer reuses the binary once it is on PATH.
PATH="$(dirname "$SNYK_BIN"):$PATH"
export PATH
sh "$SKILL/scripts/install-snyk-cli.sh" >/tmp/reinstall.out 2>/tmp/reinstall.err
if grep -q 'Using existing Snyk CLI' /tmp/reinstall.err; then
  ok "installer is idempotent (reuses existing CLI)"
else
  bad "installer is idempotent" "$(cat /tmp/reinstall.err)"
fi

# 5. Unauthenticated state is detected.
sh "$SKILL/scripts/check-snyk-auth.sh" "$SNYK_BIN" >/tmp/auth.out 2>&1
rc=$?
if [ $rc -eq 1 ] && grep -q 'authenticated: no' /tmp/auth.out; then
  ok "check-snyk-auth.sh reports unauthenticated (exit 1)"
else
  bad "check-snyk-auth.sh reports unauthenticated" "rc=$rc $(cat /tmp/auth.out)"
fi

# 6. An invalid token is rejected, and is never echoed.
fake_token="00000000-1111-2222-3333-444444444444"
SNYK_TOKEN="$fake_token" sh "$SKILL/scripts/check-snyk-auth.sh" "$SNYK_BIN" >/tmp/auth-bad.out 2>&1
rc=$?
if [ $rc -eq 1 ] && grep -q 'rejected' /tmp/auth-bad.out; then
  ok "invalid SNYK_TOKEN is rejected (exit 1)"
else
  bad "invalid SNYK_TOKEN is rejected" "rc=$rc $(cat /tmp/auth-bad.out)"
fi
if grep -q "$fake_token" /tmp/auth-bad.out; then bad "token is not printed"; else ok "token is not printed by check-snyk-auth.sh"; fi

# 7. --experimental is required.
"$SNYK_BIN" rift test >/tmp/noexp.out 2>&1
if grep -q 'SNYK-CLI-0015' /tmp/noexp.out; then
  ok "rift test without --experimental fails with SNYK-CLI-0015"
else
  bad "rift test without --experimental fails with SNYK-CLI-0015" "$(tail -5 /tmp/noexp.out)"
fi

# 8. Unauthenticated scan gives the documented error.
(cd /fixture && "$SNYK_BIN" rift test --experimental >/tmp/unauth-scan.out 2>&1)
rc=$?
if [ $rc -eq 2 ] && grep -q 'missing Snyk organization UUID' /tmp/unauth-scan.out; then
  ok "unauthenticated scan fails with exit 2 and 'missing Snyk organization UUID' (as documented)"
else
  bad "unauthenticated scan error matches SKILL.md troubleshooting" "rc=$rc $(tail -8 /tmp/unauth-scan.out)"
fi

# 9. Browser OAuth flow (local machine) prints an authorize URL with a localhost callback.
timeout 20 "$SNYK_BIN" auth >/tmp/oauth.out 2>&1
if grep -q 'https://app.snyk.io/oauth2/authorize' /tmp/oauth.out && grep -q 'redirect_uri=http%3A%2F%2F127.0.0.1' /tmp/oauth.out; then
  ok "'snyk auth' prints OAuth URL with 127.0.0.1 callback (local-only flow)"
else
  bad "'snyk auth' prints OAuth URL" "$(head -12 /tmp/oauth.out)"
fi

# 10. Remote-friendly token flow prints a login URL and keeps polling.
timeout 20 "$SNYK_BIN" auth --auth-type=token >/tmp/tokenflow.out 2>&1
rc=$?
# GNU timeout exits 124; busybox timeout exits 143 (SIGTERM).
if grep -q 'https://app.snyk.io/login?token=' /tmp/tokenflow.out && { [ $rc -eq 124 ] || [ $rc -eq 143 ]; }; then
  ok "'snyk auth --auth-type=token' prints login URL and waits (polls) for the user"
else
  bad "'snyk auth --auth-type=token' prints login URL and waits" "rc=$rc $(head -10 /tmp/tokenflow.out)"
fi

# 11. Real end-to-end scan when a token is supplied.
if [ -n "$real_token" ]; then
  export SNYK_TOKEN="$real_token"
  if sh "$SKILL/scripts/check-snyk-auth.sh" "$SNYK_BIN" >/tmp/auth-real.out 2>&1; then
    ok "real SNYK_TOKEN authenticates ($(grep '^user:' /tmp/auth-real.out))"
  else
    bad "real SNYK_TOKEN authenticates" "$(cat /tmp/auth-real.out)"
  fi

  work="$(mktemp -d)"
  cp -R /fixture/. "$work/"
  cd "$work" || exit 1
  mkdir -p .snyk-evo
  timeout 1800 "$SNYK_BIN" rift test --experimental \
    --json-file-output=.snyk-evo/results.json \
    --sarif-file-output=.snyk-evo/results.sarif \
    > .snyk-evo/console.txt 2>&1
  rc=$?
  if [ $rc -eq 0 ] || [ $rc -eq 1 ]; then
    ok "authenticated 'snyk rift test --experimental' completed (exit $rc)"
  else
    bad "authenticated 'snyk rift test --experimental' completed" "rc=$rc $(tail -15 .snyk-evo/console.txt)"
  fi
  for f in results.json results.sarif; do
    if [ -s ".snyk-evo/$f" ]; then ok "$f written"; else bad "$f written"; fi
  done
  echo "  ---- console output (tail) ----"
  tail -40 .snyk-evo/console.txt | sed 's/^/  | /'
  find "$work" -maxdepth 2 -type f | sed 's/^/  | /'
  if [ -n "${RESULTS_OUT:-}" ] && [ -d "$RESULTS_OUT" ]; then
    cp -R .snyk-evo "$RESULTS_OUT/" 2>/dev/null
    for f in rift.log fixes.md; do [ -f "$f" ] && cp "$f" "$RESULTS_OUT/"; done
  fi
  unset SNYK_TOKEN
else
  skp "real authenticated scan (set SNYK_TOKEN on the host to enable)"
fi

echo "== Result: pass=$pass fail=$fail skip=$skip"
[ $fail -eq 0 ]
