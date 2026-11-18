---
name: snyk-evo-code-scan
description: Run a Snyk Evo agentic code security scan (`snyk rift test --experimental`) on a local project, including installing the Snyk CLI and authenticating it (browser login or API token) when they are missing. Use when the user asks for an Evo code scan, an agentic or AI security scan of their code, `snyk rift`, or to find security vulnerabilities in a repository with Snyk Evo.
---

# Snyk Evo agentic code scan

Snyk Evo Code Scanning runs an agentic security analysis of a local codebase through the Snyk CLI:

```bash
snyk rift test --experimental
```

The command is **experimental**: `--experimental` is mandatory, and flags and output may change. It needs a recent Snyk CLI (it is present in 1.1308.x stable) that is authenticated to a Snyk account whose organization can run code scans.

Helper scripts live in this skill's `scripts/` directory. Set `SKILL_DIR` to the absolute path of the directory containing this `SKILL.md` (for example `~/.cursor/skills/snyk-evo-code-scan`) so the commands below work from the project directory.

## Workflow

Copy this checklist and work through it in order:

```
- [ ] 1. Snyk CLI with `rift test` available
- [ ] 2. CLI authenticated
- [ ] 3. Scan run, outcome (findings / clean / failed) determined from results.json
- [ ] 4. Findings summarized for the user
```

### 1. Get a Snyk CLI that supports `rift test`

```bash
SKILL_DIR=/absolute/path/to/snyk-evo-code-scan
SNYK_BIN="$(sh "$SKILL_DIR/scripts/install-snyk-cli.sh")"
"$SNYK_BIN" --version
```

The script logs progress to stderr and prints only the binary path to stdout, so don't merge the two streams when capturing it.

The script reuses a `snyk` already on `PATH` if it supports `rift test`. Otherwise it downloads the standalone binary for the current OS/architecture from `downloads.snyk.io`, verifies its SHA-256 checksum, and installs it to `~/.local/bin` (no root needed). Override with `SNYK_INSTALL_DIR=...`, or `SNYK_CLI_CHANNEL=preview` if stable lacks the command.

Use `"$SNYK_BIN"` (the full path) for every later command, because the install directory may not be on `PATH`.

Alternatives if the script cannot run: `npm install -g snyk`, `brew tap snyk/tap && brew install snyk`, or on Windows `scoop install snyk` / download `https://downloads.snyk.io/cli/stable/snyk-win.exe`. Afterwards confirm `snyk rift test --help` shows the `--experimental` flag.

### 2. Make sure the CLI is authenticated

```bash
sh "$SKILL_DIR/scripts/check-snyk-auth.sh" "$SNYK_BIN"
```

Exit code 0 means authenticated; skip to step 3. Exit code 1 means not authenticated; the output names the credential source it tried and the reason (for example `401 Unauthorized`). Authenticate with one of the methods below. **Pick the method based on what is available — do not guess:**

1. **`SNYK_TOKEN` is already set** in the environment: the CLI reads it automatically, so if the check passed there is nothing to do. If the check failed with `401`, the token is invalid, expired, or belongs to another region. If the user's region is unknown, you may retry the check once with each regional `SNYK_API` (see Regions below). If none work, ask the user for a new token or offer the browser login (method 3). `SNYK_TOKEN` overrides stored credentials, so `unset SNYK_TOKEN` before using method 3.
2. **The user can give you a token** (personal API token from https://app.snyk.io/account, or a service account token): ask the user to set it as the `SNYK_TOKEN` environment variable for your session (or in their agent's secrets settings). If they hand it to you directly, export it rather than passing it on the command line:

   ```bash
   export SNYK_TOKEN='<token>'   # never echo it, log it, or write it into the repo
   ```

   Use `"$SNYK_BIN" auth "$SNYK_TOKEN"` only if the user wants the token persisted in the CLI config for future sessions.
3. **Interactive browser login.** Start it in the background, because it blocks until the user finishes:
   - **The agent runs on the user's own machine** (local IDE/terminal): run `"$SNYK_BIN" auth`. It tries to open a browser; it also prints a URL starting with `https://app.snyk.io/oauth2/authorize?...`. Show the user that URL. The OAuth callback goes to `http://127.0.0.1:8080` on **this** machine, so it only completes in a browser on the same machine.
   - **The agent runs remotely** (cloud agent, container, SSH, CI): use `"$SNYK_BIN" auth --auth-type=token`. It prints a URL like `https://app.snyk.io/login?token=...`. The user can open this in a browser on any device; the CLI polls Snyk and finishes on its own once they log in, storing an API token in the CLI config.

   Tell the user exactly which URL to open. The `token=`/`code_challenge` values in these login URLs are one-time login handles, not credentials, so sharing the URL with the user is fine. Keep the auth process running while they log in: the URL is tied to that process, so if it is killed or times out, start a new one and send the new URL. Poll `check-snyk-auth.sh` (or wait for the auth process to exit) every 10-15 seconds for up to about 5 minutes, then continue. If the user does not complete login in that time, stop the auth process and ask them to tell you when they are ready.
4. **Service accounts with OAuth client credentials**: `"$SNYK_BIN" auth --auth-type=oauth --client-id="$SNYK_CLIENT_ID" --client-secret="$SNYK_CLIENT_SECRET"`.

If you cannot authenticate (no token, user unavailable for the browser step), stop and tell the user what is needed. Do not try other workarounds.

**Regions:** the default endpoint is US-01 (`https://api.snyk.io`). Tokens from other regions need the matching endpoint: `https://api.us.snyk.io` (US-02), `https://api.eu.snyk.io` (EU), or `https://api.au.snyk.io` (AU). Set it with `export SNYK_API=<url>` or `"$SNYK_BIN" config set endpoint=<url>`. The browser OAuth flow handles regions automatically.

### 3. Run the scan

Run from the project root (or `cd` there first). Scans can take several minutes on larger repositories, so use a generous timeout or run it in the background and poll.

```bash
mkdir -p .snyk-evo
rm -f .snyk-evo/results.json .snyk-evo/results.sarif
"$SNYK_BIN" rift test --experimental \
  --json-file-output=.snyk-evo/results.json \
  --sarif-file-output=.snyk-evo/results.sarif \
  > .snyk-evo/console.txt 2>&1
scan_rc=$?
cat .snyk-evo/console.txt
sh "$SKILL_DIR/scripts/summarize-results.sh" .snyk-evo/results.json "$scan_rc"
```

The `rm -f` matters: a results file left over from an earlier run would otherwise be mistaken for the result of a scan that failed.

Useful flags (check `"$SNYK_BIN" rift test --help` for the current list, since the command is experimental):

| Flag | Purpose |
|------|---------|
| `--org=<org-id-or-slug>` | Use a specific Snyk organization instead of the account's preferred one |
| `--severity-threshold=low\|medium\|high\|critical` | Only report findings at or above this severity |
| `--focus=<name>` | Ask the scan to prioritize a class of issues |
| `--json`, `--sarif`, `--html` | Print machine-readable output to stdout instead of the console report |
| `--json-file-output`, `--sarif-file-output`, `--html-file-output` | Write that format to a file in addition to the console report |
| `--include-ignores` | Include findings that have been ignored in Snyk |
| `-d` | Debug logging (very verbose; use when diagnosing failures) |

**Do not decide whether the scan found anything from the exit code.** `rift test` returns `0` both when it finds vulnerabilities and when it finds none, so `0` only means the scan ran. It does not follow the usual Snyk convention of `1` for findings (`1` has not been observed, but if you see it, treat it like `0` and trust the results file). Observed behavior:

| Situation | Exit code | `results.json` | Console |
|-----------|-----------|----------------|---------|
| Vulnerabilities found | `0` | `{"findings":[...]}` | `N vulnerabilities found.` |
| Clean project | `0` | `{"findings":[]}` | `No vulnerabilities found.` |
| Scan failed (bad token, nothing scannable, ...) | `2` | not written | an `ERROR` block |

`summarize-results.sh` applies these rules and prints `scan outcome: findings`, `clean`, or `failed`. It exits `0` when the scan completed (with or without findings) and `1` when it did not. Report exactly what it says: never describe a `failed` outcome as "no issues found", and never describe a `clean` outcome as a failure because of the exit code. It uses `jq` or `python3` when installed; otherwise it falls back to `grep` and lists only severity and title, so read `results.json` for locations and details.

`results.sarif` currently contains the same JSON as `results.json`, not SARIF, so don't pass it to tools that expect SARIF; use `results.json`.

The scan may also write `rift.log` (full details) and `fixes.md` (fix prompts for each finding) in the working directory; read them if present. Add `.snyk-evo/`, `rift.log`, and `fixes.md` to `.gitignore` or delete them afterwards unless the user wants them kept; do not commit scan output unasked.

### 4. Report the results

Use the `scan outcome` from step 3 and summarize for the user, most severe first:

- The outcome (`findings`, `clean`, or `failed`). If `failed`, say so and why instead of reporting results.
- Total findings by severity.
- For each high/critical finding: title, file and line, why it is exploitable, and the suggested fix.
- Where the full results are (`.snyk-evo/results.json`, `results.sarif`, `fixes.md`).

Only change code to fix findings if the user asks. After fixing, re-run the scan to confirm the findings are gone.

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `Command is experimental (SNYK-CLI-0015)` | Add `--experimental`. |
| `missing Snyk organization UUID — run snyk auth or pass --org` | Almost always means the CLI is **not authenticated** or the token is invalid. Run `check-snyk-auth.sh`. If auth is fine, pass `--org=<org-id>` or run `snyk config set org=<org-id>`. |
| `no scannable files found here` (exit `2`, no results file) | The directory has no source files the scan can use: everything was ignored, binary, empty, or over 1 MB. Run from the project root, or check `.gitignore`/`.snykignore`. |
| `Unspecified Error (SNYK-CLI-0000)` with exit `2` | The scan failed; read the detail lines below the error. Bad credentials produce this too, so re-run `check-snyk-auth.sh`. |
| `401 Unauthorized` / `SNYK-0005` | Token invalid, expired, or wrong region. Re-authenticate or set `SNYK_API`. |
| `code scanning is off ... until an admin fixes it` | The organization does not have Snyk Code / Evo code scanning enabled. A Snyk org admin must enable it, or use `--org` for an org where it is enabled. |
| `rift test --help` prints the general CLI help | The CLI is too old. Re-run `install-snyk-cli.sh` with `SNYK_FORCE_INSTALL=1` (or `SNYK_CLI_CHANNEL=preview`). |
| `snyk auth` hangs on a remote machine | The OAuth callback cannot reach `127.0.0.1:8080`. Kill it and use `snyk auth --auth-type=token` or `SNYK_TOKEN`. |
| Browser errors such as `Missing X server or $DISPLAY` during `snyk auth` | Harmless on headless machines; use the printed URL. |
| Network or TLS errors | Corporate proxy: set `HTTPS_PROXY`; custom CA: set `NODE_EXTRA_CA_CERTS`. As a last resort, and only with user consent, `--insecure`. |

For deeper diagnosis run the failing command with `-d` and pipe it to `snyk doctor --stdin`.

## Security rules

- Never print, log, or commit `SNYK_TOKEN` or any credential. Don't put tokens directly in command lines that get echoed into transcripts.
- Don't disable TLS verification (`--insecure`) without the user's explicit consent.
- Scan output can contain code snippets from the repository; treat it as sensitive as the code itself.
