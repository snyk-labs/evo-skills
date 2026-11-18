# Snyk Evo Skills

A curated collection of [Agent Skills](https://agentskills.io) that help AI coding agents (Cursor, Claude Code, Codex, and others) use Snyk Evo capabilities.

## Skills

| Skill | What it does |
|-------|--------------|
| [`snyk-evo-code-scan`](skills/snyk-evo-code-scan/SKILL.md) | Runs the experimental Evo agentic code security scan (`snyk rift test --experimental`). Installs the Snyk CLI if it is missing, authenticates it through browser login or an API token, and summarizes the findings. |

## Installing a skill

Each skill is a self-contained directory under `skills/`. Copy (or symlink) it into the skills directory of your agent:

| Agent | Project-level | User-level |
|-------|---------------|------------|
| Cursor | `.cursor/skills/` | `~/.cursor/skills/` |
| Claude Code | `.claude/skills/` | `~/.claude/skills/` |
| Codex / others | `.agents/skills/` | `~/.agents/skills/` |

```bash
git clone https://github.com/snyk-labs/evo-skills.git
mkdir -p ~/.cursor/skills
cp -R evo-skills/skills/snyk-evo-code-scan ~/.cursor/skills/
```

Then ask your agent something like *"Run a Snyk Evo code scan on this repo"*.

## Testing

`tests/isolated/run.sh` checks each skill in fresh Docker containers (Ubuntu, Debian, Alpine) as a non-root user with no Snyk CLI and no credentials. It confirms that the CLI can be installed from scratch (checksum verified), that each authentication path behaves as the skill describes, and that the documented error messages match the real CLI.

```bash
tests/isolated/run.sh                      # all images
tests/isolated/run.sh alpine:3.20          # one image
SNYK_TOKEN=<token> tests/isolated/run.sh   # also run a real authenticated scan on tests/fixtures/vulnerable-app
```

Results of authenticated runs are copied to `tests/isolated/out/` (git-ignored).

## Contributing a skill

- One directory per skill under `skills/<skill-name>/`, containing a `SKILL.md` with `name` (matching the directory name) and `description` frontmatter.
- Keep `SKILL.md` focused; put helper scripts in `scripts/`.
- Add isolated tests that exercise the skill from a clean environment.
