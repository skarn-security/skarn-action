# Skarn + Trunk integration

Run Skarn (AI-session secret scanner) inside the Trunk-managed pipelines a team
already operates, beside trufflehog / semgrep / osv-scanner, as the AI-session
security layer none of those cover.

Skarn fits Trunk's **Action** model better than its Linter model: its findings live
in AI session transcripts under `$HOME` (`~/.claude`, `~/.codex`, ...), not in repo
lines, and Trunk linters run in a hermetic sandbox that may not see `$HOME`. So
**lead with the Action (Shape A) for gating**; the SARIF Linter (Shape B) is an
optional visibility add-on where the sandbox permits `$HOME` reads.

> Scoping note: `--project <p>` keeps sessions whose project name starts with `<p>`,
> and Skarn derives that name as the repo **basename** (e.g. `skarn`), not the absolute
> path - so pass `--project "$(basename ${workspace})"`, not `--project ${workspace}`
> (the latter matches nothing). Trade-off: two repos sharing a basename would both
> match; omit `--project` for a host-wide scan of all sessions.

## Shape A (recommended): gating Action

Add to `.trunk/trunk.yaml`. Scopes to this repo's sessions via `--project` (see the
scoping note above), reads `~/.claude` etc. with the normal env, and fails the hook
on findings at/above a threshold.

```yaml
actions:
  enabled:
    - skarn-pre-push
  definitions:
    - id: skarn-pre-push
      display_name: Skarn (AI session secret scan)
      triggers:
        - git_hooks: [pre-push]
      run: skarn check --project "$(basename ${workspace})" --fail-on-severity high
```

`skarn check` needs a license: the free one is issued at https://getskarn.com/free?utm_source=trunk-readme&utm_medium=referral&utm_campaign=free&utm_content=license after a quick email confirmation, installed once with `skarn license <file>` and read from `~/.config/skarn/license`, or supplied to a CI runner as the `SKARN_LICENSE` environment variable. Without one, `skarn check` exits 7 and Trunk fails the action with skarn's own message naming the fix - never a bare exit code.

Rollout discipline (mirrors the skarn-guard / Socket-Firewall lesson): start at
`pre-push` and report-only, then tighten.

- Observe first: `run: skarn check --project "$(basename ${workspace})"` with no gating
  flags (surfaces findings without failing the hook; a missing license or scan error
  still exits nonzero).
- Then enforce: `--fail-on-severity high` (exit 1 on high+), or
  `--fail-on-risk 70` (exit 2 above a session risk score).
- Or keep the whole gate in version control with policy-as-code:
  `--policy .skarn-policy.toml` (declares fail thresholds, required/forbidden rules,
  and baseline enforcement; the `--fail-on-*` flags override it). Exit 4 means a policy
  precondition was unmet.
- Fail only on NEW findings (skip pre-existing): add a committed baseline,
  `--baseline .skarn-baseline.json` (generate once with
  `skarn check --project . --baseline .skarn-baseline.json --baseline-create`). For a
  team, commit a `baseline.d/` directory of per-member files and point `--baseline` at it.
- Leave compliance evidence: `--audit-log .skarn-audit.ndjson` appends a tamper-evident
  record of each run. For a SIEM, `--format ndjson` streams findings to your collector.
- Optional: `--check-packages` to also flag typosquat/URL installs in sessions.

## Shape B (optional): SARIF Linter for `trunk check` + GitHub code scanning

```yaml
lint:
  definitions:
    - name: skarn
      files: [ALL]
      commands:
        - name: check
          output: sarif
          read_output_from: stdout
          run: skarn check --project "$(basename ${workspace})" --format sarif
          success_codes: [0, 1]
  enabled:
    - skarn@SYSTEM
```

Caveats:
- **License**: exit 7 (no license installed) is outside `success_codes: [0, 1]`, so Trunk surfaces a missing license as a tool failure carrying skarn's own message, which names the fix. That is deliberate - do NOT add 7 to `success_codes`, or a run that never scanned would be reported as success.
- **Sandbox / `$HOME`**: Trunk linters run hermetically; verify the linter can read
  `~/.claude` (try `run_linter_from: workspace` and a relaxed sandbox). If `$HOME`
  is blocked, Shape B is infeasible - use Shape A. **This is the gating experiment.**
- **Out-of-repo locations**: SARIF results point at session files, which Trunk's
  file-centric UI cannot map to repo lines. Treat linter output as informational.
- **Hold-the-line**: Skarn's SARIF already carries `partialFingerprints`
  (`skarn/v1` = the secret-scoped fingerprint) for cross-run dedupe, but because
  findings are out-of-repo, prefer Skarn's own `--baseline` as the source of truth for
  "new findings" over Trunk's branch baseline.

## Distribution

- **Inline** (above): copy into `.trunk/trunk.yaml`. Zero infra.
- **Plugin repo**: see `plugin.yaml` here; users add it under `plugins.sources` and
  run `trunk check enable skarn`.
- Binary provisioning: `@SYSTEM` (use the brew-installed `skarn` on `PATH`) or a
  `tools.definitions` entry downloading the release artifact.
