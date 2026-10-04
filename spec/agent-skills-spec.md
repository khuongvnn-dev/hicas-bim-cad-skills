# Agent Skills Spec

The spec is located at <https://agentskills.io/specification>

Rules this repo follows (checked when a skill is added or changed):

- One folder per skill under `skills/`, folder name = `name` (lowercase, digits, single hyphens, ≤ 64 chars).
- `SKILL.md` frontmatter only uses `name`, `description` (≤ 1024 chars), and optionally `license`,
  `compatibility` (≤ 500 chars), `metadata` (string → string), `allowed-tools`.
- Claude Code-only options (usage hint, preferred model) go into `metadata`, not top-level keys.
- `SKILL.md` stays under 500 lines; detail goes to `references/`, templates/data to `assets/`,
  executable code to `scripts/`, referenced with relative paths one level deep.
