# Agent instructions

This repository holds Agent Skills for Snyk Evo. It is not an application. The procedure for a scan lives in [`skills/snyk-evo-code-scan/SKILL.md`](skills/snyk-evo-code-scan/SKILL.md). Read that file and follow it. The notes here are the rules that change the result when they are skipped.

## When to scan

Run this skill when the user asks for an Evo code scan, an agentic or AI security scan, `snyk rift`, or for Snyk Evo to find security vulnerabilities.

Scan the project the user names, from its root. When the user says "this project" and the workspace is some other repository, scan that repository. Do not scan this skills repository unless the user asks. `tests/fixtures/vulnerable-app` is an intentionally vulnerable fixture for the tests. Scan it only when the user asks to exercise the skill. Do not fix it, and do not report its findings as defects in this repository.

## How to scan

Set `SKILL_DIR` to the absolute path of `skills/snyk-evo-code-scan` in this checkout. Use `"$SNYK_BIN"` for every Snyk command after install. The installer puts the binary in `~/.local/bin` and does not add that directory to `PATH`.

1. Install or reuse the CLI. The script prints only the binary path on stdout and logs on stderr. Do not merge the two streams.

   ```bash
   SNYK_BIN="$(sh "$SKILL_DIR/scripts/install-snyk-cli.sh")"
   "$SNYK_BIN" --version
   ```

2. Check authentication.

   ```bash
   sh "$SKILL_DIR/scripts/check-snyk-auth.sh" "$SNYK_BIN"
   ```

   Exit 0 means continue. Exit 1 means not authenticated. Follow the authentication section in `SKILL.md` and pick the method from what is actually available:

   - `SNYK_TOKEN` is already set: the CLI reads it. If the check returns 401, the token is invalid, expired, or for another region. When the region is unknown, retry the check once each with `SNYK_API` set to `https://api.us.snyk.io`, `https://api.eu.snyk.io`, and `https://api.au.snyk.io`. Unset `SNYK_API` if none of them work. The default, with `SNYK_API` unset, is US-01 (`https://api.snyk.io`). If none work, ask the user. Do not keep guessing.
   - The user can supply a token: ask them to set `SNYK_TOKEN` for the session. If they hand it to you, `export` it. Never echo it, log it, or write it into the repo, and do not pass it as a command argument.
   - The agent is on the user's own machine: run `"$SNYK_BIN" auth` and show the user the `https://app.snyk.io/oauth2/authorize?...` URL. The callback is `127.0.0.1` on that machine.
   - The agent is remote (cloud agent, container, SSH, CI): run `"$SNYK_BIN" auth --auth-type=token` and show the user the `https://app.snyk.io/login?token=...` URL. `snyk auth` without `--auth-type=token` cannot finish remotely, because the callback never reaches `127.0.0.1`.

   Keep the login process running while the user logs in, and poll every 10–15 seconds for up to 5 minutes. If you cannot authenticate, stop and say what the user needs to provide.

3. From the project root, delete any previous results and run the scan. A scan can take several minutes. Keep the exit code.

   ```bash
   mkdir -p .snyk-evo
   rm -f .snyk-evo/results.json .snyk-evo/results.sarif
   "$SNYK_BIN" rift test --experimental \
     --json-file-output=.snyk-evo/results.json \
     --sarif-file-output=.snyk-evo/results.sarif \
     > .snyk-evo/console.txt 2>&1
   scan_rc=$?
   ```

4. Classify the run from the results file, not from the exit code.

   ```bash
   sh "$SKILL_DIR/scripts/summarize-results.sh" .snyk-evo/results.json "$scan_rc"
   ```

## Rules that change the result

- `rift test` exits 0 when it finds vulnerabilities and when it finds none. Exit 0 means the scan ran. It does not mean the project is clean. Exit 2 means the scan failed, and the results file is not written.
- Report the `scan outcome` line from `summarize-results.sh`: `findings`, `clean`, or `failed`. Never describe `failed` as "no vulnerabilities found". Never describe `clean` as a failure because the exit code was 0.
- `summarize-results.sh` exits 0 when the scan completed, with or without findings, and exits 1 when it did not. Its exit code is not the Snyk CLI exit code.
- `.snyk-evo/results.sarif` is the same JSON as `results.json` in the current CLI, not SARIF. Use `results.json` for locations, descriptions, and fix plans. Read `rift.log` and `fixes.md` in the project root when they exist.
- Do not commit `.snyk-evo/`, `rift.log`, `fixes.md`, or `tests/isolated/out/`.
- Never print, log, or commit `SNYK_TOKEN` or any other credential.
- Do not change code to fix findings unless the user asks. After a requested fix, run the scan again and compare the new outcome.

## What to tell the user

Lead with the outcome. For `findings`, give the count by severity, then each high and critical finding with its title, file and line, why it is exploitable, and the suggested fix. Say where the full results are. For `failed`, say why, using the console output and the troubleshooting table in `SKILL.md`, and do not invent a clean result.
