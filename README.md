# Skarn GitHub Action

Scan what your CI's AI agent did. When an AI coding agent (Claude Code, Codex CLI, Cursor, Copilot) runs inside a GitHub Action or devcontainer, it leaves session transcripts under `$HOME` (`~/.claude`, `~/.codex`, ...). This Action runs `skarn check` over those transcripts before the job ends, surfaces leaked credentials and attack patterns, writes a SARIF report for the code-scanning Security tab, and can fail the job on a severity or risk threshold.

This is not a repo or git-history secret scanner. Skarn reads AI-session logs and agent activity, not your source tree or commit history - use a dedicated secret scanner for those. Skarn covers the surface they do not: what the assistant saw, wrote, and ran in the session.

## What it does

- Runs `skarn check --format sarif` scoped to the AI session logs present on the runner.
- Writes a redacted SARIF 2.1.0 report (secrets are masked in every output; the raw value never appears).
- Developer feedback is on by default: a job summary table and per-finding workflow annotations, both without any extra token or permission.
- Honors `fail-on-severity` (exit 1) and `fail-on-risk` (exit 2) for CI gating; report-only until you set one.
- Emits `risk-score`, `findings-count`, `exit-code`, and `sarif-file` as outputs.

## Usage

```yaml
- name: Skarn AI-session scan
  uses: skarn-security/skarn-action@v1
  with:
    version: "0.15.0"
    fail-on-severity: high
```

Send the findings to the GitHub code-scanning Security tab by uploading the SARIF (needs `security-events: write` on the job):

```yaml
- name: Skarn AI-session scan
  id: skarn
  uses: skarn-security/skarn-action@v1
  with:
    version: "0.15.0"
    sarif-file: skarn-results.sarif
- name: Upload SARIF to code scanning
  if: always()
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: skarn-results.sarif
    category: skarn
```

A full agent-then-scan workflow is in [`examples/agentic-ci.yml`](examples/agentic-ci.yml).

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `skarn-path` | (empty) | Path to a pre-installed `skarn` binary. If set, or if `skarn` is already on `PATH`, the download step is skipped. |
| `version` | `latest` | Skarn version to download when no binary is on `PATH`. Pin a concrete version (for example `0.15.0`); `latest` is rejected because there is no version to resolve without a network lookup. |
| `download-base-url` | skarn-dist releases | Base URL the binary is fetched from: `<base>/v<version>/skarn-<arch>-<os>`. |
| `hours` | (Skarn default 720) | Scan window in hours; `0` means no limit. |
| `cli` | (all) | Restrict to one assistant: `claude`, `gemini`, `codex`, `cursor`, `copilot`. |
| `project` | (all) | Restrict to sessions under this project path. |
| `severity` | (Skarn default medium) | Report only findings at or above this severity. |
| `fail-on-severity` | (empty, report-only) | Fail the job (exit 1) if any finding is at or above this severity. |
| `fail-on-risk` | (empty, report-only) | Fail the job (exit 2) if the session risk score exceeds this 0-100 threshold. |
| `sarif-file` | `skarn-results.sarif` | Path the SARIF report is written to. |
| `soft-fail` | `false` | Never fail the job on findings; still report. |
| `job-summary` | `true` | Write a findings summary to the GitHub job summary. |
| `annotations` | `true` | Emit per-finding workflow annotations. |
| `license` | (empty) | Skarn license token, exported as `SKARN_LICENSE` for paid flags. The free core needs none. |
| `extra-args` | (empty) | Additional arguments appended to the `skarn check` invocation, split on whitespace (quoted values with spaces are not preserved). |

## Outputs

| Output | Description |
| --- | --- |
| `sarif-file` | Path to the written SARIF report. |
| `exit-code` | The `skarn check` exit code (0 clean, 1 fail-on-severity, 2 fail-on-risk, 3 canary, 6 scan error). |
| `risk-score` | Session risk score (0-100) parsed from the SARIF report. |
| `findings-count` | Number of findings in the SARIF report. |

## Binary acquisition

The Action ships only this config and a thin wrapper; it never embeds the binary or any non-public rules. It resolves `skarn` in order: an explicit `skarn-path`, then `skarn` on `PATH`, then a download of the pinned `version` from `download-base-url`. Point `skarn-path` at a binary you install in an earlier step, or pin `version` once the public release channel is live. The free core needs no license; supply `license` only when you pass a paid flag through `extra-args`.

The download branch fetches a raw binary over HTTPS and does not yet verify a checksum or signature; for a supply-chain-sensitive pipeline, install `skarn` in an earlier step with your own verification (the OCI image is cosign-signed with an SBOM) and pass `skarn-path`. Signed-download verification for this path lands with the public release channel.

## What appears where

Findings live in AI-session files under `$HOME`, not in your repository tree, so the SARIF result locations point at session file paths rather than repo lines. GitHub code scanning ingests the SARIF and lists the findings in the Security tab, but it cannot anchor them to a pull-request diff line (there is no matching source line). The always-on job summary and workflow annotations are therefore the primary developer-facing surface; the SARIF upload is the durable Security-tab record and cross-run dedupe (via `partialFingerprints`).

## Runner support

The wrapper is a Bash composite step: Linux and macOS runners are supported. Windows runners are not (`skarn.exe` and `skarn guard` still work directly; only this Action's wrapper is Bash-only).

## Real-time alternative

This Action is the batch, after-the-fact path. For real-time, pre-execution blocking inside an agent, use `skarn guard` (a hook that vets each tool call before it runs). See the plugin integrations under `integrations/`.

## License

This Action - the `action.yml` manifest, the wrapper scripts, and these docs - is released under the MIT License (see `LICENSE`). It ships configuration and a thin wrapper only. The `skarn` binary it downloads and runs is proprietary software, licensed separately; see https://getskarn.com and the license distributed with the binary.
