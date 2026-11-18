# Snyk Evo Skills

A curated collection of [Agent Skills](https://agentskills.io) that help AI coding agents (Cursor, Claude Code, Codex, and others) use Snyk Evo.

An agent that opens this repository reads [AGENTS.md](AGENTS.md) first, then the skill it names. [AGENTS.md](AGENTS.md) points at the scan procedure and records the rules that change a scan result.

## Skills

| Skill | What it does |
|-------|--------------|
| [`snyk-evo-code-scan`](skills/snyk-evo-code-scan/SKILL.md) | Runs an Evo agentic code security scan (`snyk rift test --experimental`) on a local project. Installs the Snyk CLI when it is missing, authenticates with a browser login or an API token, and reports whether the scan found vulnerabilities, found none, or failed. |

## What a scan needs

- A Snyk account whose Organization has Evo code scanning enabled.
- A credential. Set `SNYK_TOKEN` for the agent session, or complete the browser login the skill prints. With `SNYK_API` unset, the CLI uses the US-01 region (`https://api.snyk.io`). A token from another region needs `SNYK_API`. The skill lists the regional endpoints.
- A Snyk CLI that provides `rift test`. The skill installs the current stable CLI when the command is missing. Snyk CLI 1.1308.4 stable includes it. `--experimental` is required.

## Installing a skill

Each skill is a self-contained directory under `skills/`. Copy or symlink it into the skills directory of your agent:

| Agent | Project-level | User-level |
|-------|---------------|------------|
| Cursor | `.cursor/skills/` | `~/.cursor/skills/` |
| Claude Code | `.claude/skills/` | `~/.claude/skills/` |
| Codex and others | `.agents/skills/` | `~/.agents/skills/` |

```bash
git clone https://github.com/snyk-labs/evo-skills.git
mkdir -p ~/.cursor/skills
cp -R evo-skills/skills/snyk-evo-code-scan ~/.cursor/skills/
```

Then ask the agent to run a Snyk Evo code scan on the project. The agent follows `SKILL.md`.

You can also point an agent at this repository without copying the skill. [AGENTS.md](AGENTS.md) tells it to use `skills/snyk-evo-code-scan` from this checkout.

## How the code scan works

The procedure is [`skills/snyk-evo-code-scan/SKILL.md`](skills/snyk-evo-code-scan/SKILL.md). The agent does the following:

1. Set `SKILL_DIR` to the absolute path of the directory that contains `SKILL.md`. In this checkout that is `skills/snyk-evo-code-scan`.
2. Run `scripts/install-snyk-cli.sh`. The script prints the `snyk` path on stdout and logs on stderr.
3. Run `scripts/check-snyk-auth.sh`. When the check fails, authenticate with the method `SKILL.md` selects for that machine. A remote agent uses `snyk auth --auth-type=token` or `SNYK_TOKEN`. Plain `snyk auth` only finishes on the user's own machine, because the callback is `127.0.0.1`.
4. From the project root, run `snyk rift test --experimental` and write `.snyk-evo/results.json`.
5. Run `scripts/summarize-results.sh` on that file and report the outcome it prints.

`rift test` exits 0 both when it finds vulnerabilities and when it finds none. Exit 0 means the scan ran. The results file decides the outcome:

| Outcome | What the summarizer prints | Meaning |
|---------|----------------------------|---------|
| Findings | `scan outcome: findings` | The `findings` array lists vulnerabilities. |
| Clean | `scan outcome: clean` | The scan finished and `findings` is empty. |
| Failed | `scan outcome: failed` | The scan did not finish. This is not a clean project. |

The scan also writes `.snyk-evo/console.txt`, and it can write `rift.log` and `fixes.md` in the project root. Do not commit those files, or `.snyk-evo/`, unless you intend to keep them. In the current CLI, `results.sarif` is the same JSON as `results.json`, so use `results.json`.

Never print, log, or commit `SNYK_TOKEN`.

## Testing

`tests/isolated/run.sh` runs the skill in fresh Docker containers (Ubuntu 24.04, Debian 12, and Alpine 3.20) as a non-root user with no Snyk CLI and no credentials. It checks that the CLI installs from scratch and the checksum matches, that each authentication path behaves as the skill describes, that the documented errors match the real CLI, and that `summarize-results.sh` classifies findings, a clean result, and a failed scan correctly.

```bash
tests/isolated/run.sh                      # all images
tests/isolated/run.sh alpine:3.20          # one image
SNYK_TOKEN=<token> tests/isolated/run.sh   # also run a real authenticated scan
```

With `SNYK_TOKEN` set, the script scans `tests/fixtures/vulnerable-app` (an intentionally vulnerable fixture), a clean project, and a directory with nothing to scan. Results of authenticated runs are copied to `tests/isolated/out/` (git-ignored). Do not commit that directory.

## Contributing a skill

- One directory per skill under `skills/<skill-name>/`, containing a `SKILL.md` with `name` (matching the directory name) and `description` frontmatter.
- Keep `SKILL.md` focused. Put helper scripts in `scripts/`.
- Add isolated tests that exercise the skill from a clean environment.
- Update [AGENTS.md](AGENTS.md) when a skill changes the steps an agent must run.
