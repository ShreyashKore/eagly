# Agent skills

Skills for this repo live here — **`.agents/skills/` is the source of truth**,
one directory per skill holding a `SKILL.md`:

```
.agents/skills/<skill-name>/SKILL.md
```

The layout is deliberately agent-agnostic. `.claude/skills` is a symlink to this
directory, so Claude Code picks the same skills up with no copying and nothing
to keep in sync; other agents get their own symlink alongside it. Add a skill
once, here, and every agent sees it.

Verified: Claude Code follows the symlink and lists skills defined here.

## Adding a skill

```bash
mkdir -p .agents/skills/my-skill
$EDITOR .agents/skills/my-skill/SKILL.md
```

`SKILL.md` opens with YAML frontmatter — `name` (matching the directory) and a
`description` that says *when* to reach for it, since that line is all an agent
sees when deciding whether to load the skill:

```markdown
---
name: my-skill
description: What it does, and the situations that should trigger it.
---

# My skill

Instructions for the agent.
```

Restart the agent session to pick up a newly added skill.

On Windows, git only materialises `.claude/skills` as a real symlink with
Developer Mode on and `core.symlinks=true`; otherwise it lands as a text file
holding the path and every skill silently disappears. `scripts/setup.sh` checks
for this and says how to fix it.

## Wiring another agent

Point its skills directory here rather than copying files into it:

```bash
ln -s ../.agents/skills .<agent>/skills
```
