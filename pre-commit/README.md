# Skarn + pre-commit

Add Skarn to a [pre-commit](https://pre-commit.com) chain so a batch AI-session scan runs at commit time, next to the secret scanners a team already runs. The hook is defined in `.pre-commit-hooks.yaml` at the repo root.

## Honest scope

This hook runs `skarn check` over the AI coding-assistant session logs on your machine (`~/.claude`, `~/.codex`, ...); it does not scan the staged diff. Skarn's surface is what the AI assistant saw, wrote, and ran, not your source tree, so `pass_filenames` is off and the staged file list is not passed to it. This is the batch path. The real-time, pre-execution path is `skarn guard` (a hook that vets each agent tool call before it runs); see the plugin integrations under `integrations/`.

Because it scans all in-window sessions rather than staged files, keep the window small and the gate explicit via `args`.

## Use it

In your `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/skarn-security/skarn-action
    rev: v0.19.0
    hooks:
      - id: skarn
        args: [--hours, "24", --fail-on-severity, high]
```

`skarn` must be on `PATH` (`language: system`). Install it first (`brew install skarn-security/tap/skarn` or the release binary). The hook fails the commit when a finding is at or above the `--fail-on-severity` you set; with no gating flag it reports findings without blocking on them. Gating flags govern findings only - a setup failure such as a missing license still fails the commit regardless (see below).

`skarn check` needs a license. The free one is issued at https://getskarn.com/free after a quick email confirmation; install it once with `skarn license <file>` and every local run reads it from `~/.config/skarn/license`. The hook needs no change and no secret: it runs on your own machine, where your personal license is already installed. Without a license `skarn check` exits 7 and prints how to register, so the commit fails with that message rather than a bare exit code.

Useful `args`:

- `--hours <n>` - scan window; `0` means no limit.
- `--cli <name>` - restrict to one assistant (`claude`, `gemini`, `codex`, `cursor`, `copilot`).
- `--fail-on-severity <level>` / `--fail-on-risk <n>` - CI-style gating.
- `--baseline <file>` - suppress accepted findings and fail only on new ones; without it, `~/.config/skarn/baseline.json` applies automatically when present.

## Distribution

The `id: skarn` hook is hosted from the same distribution repo as the GitHub Action; the `repo:`/`rev:` above track that repo and the release tag. The `.pre-commit-hooks.yaml` manifest is generated into the distribution repo at each release, never hand-edited.
