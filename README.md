# Skarn GitHub Action

Scan what your CI's AI agent did. When an AI coding agent (Claude Code, Codex CLI, Cursor, Copilot) runs inside a GitHub Action or devcontainer, it leaves session transcripts under `$HOME` (`~/.claude`, `~/.codex`, ...). This Action runs `skarn check` over those transcripts before the job ends, surfaces leaked credentials and attack patterns, writes a SARIF report for the code-scanning Security tab, and can fail the job on a severity or risk threshold.

This is not a repo or git-history secret scanner. Skarn reads AI-session logs and agent activity, not your source tree or commit history - use a dedicated secret scanner for those. Skarn covers the surface they do not: what the assistant saw, wrote, and ran in the session.

## What it does

- Runs `skarn check --format sarif` scoped to the AI session logs present on the runner.
- Writes a redacted SARIF 2.1.0 report (secrets are masked in every output; the raw value never appears).
- Developer feedback is on by default: a job summary table and per-finding workflow annotations, both without any extra token or permission.
- Honors `fail-on-severity` (exit 1) and `fail-on-risk` (exit 2) for CI gating; report-only until you set one.
- Emits `risk-score`, `findings-count`, `exit-code`, `skipped`, and `sarif-file` as outputs.

## Usage

```yaml
- name: Skarn AI-session scan
  uses: skarn-security/skarn-action@v1
  with:
    version: "0.20.0"
    license: ${{ secrets.SKARN_LICENSE }}
    fail-on-severity: high
```

Send the findings to the GitHub code-scanning Security tab by uploading the SARIF (needs `security-events: write` on the job):

```yaml
- name: Skarn AI-session scan
  id: skarn
  uses: skarn-security/skarn-action@v1
  with:
    version: "0.20.0"
    license: ${{ secrets.SKARN_LICENSE }}
    sarif-file: skarn-results.sarif
- name: Upload SARIF to code scanning
  if: always() && steps.skarn.outputs.skipped != 'true'
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: skarn-results.sarif
    category: skarn
```

A full agent-then-scan workflow is in [`examples/agentic-ci.yml`](examples/agentic-ci.yml).

## Skarn license

`skarn check` needs a license. The free one is issued at https://getskarn.com/free?utm_source=action-readme&utm_medium=referral&utm_campaign=free&utm_content=license-section after a quick email confirmation: register, download the license file, and store its contents as a repository secret (for example `SKARN_LICENSE`). Pass it with `license: ${{ secrets.SKARN_LICENSE }}`. The binary still verifies the license offline against a key embedded in it - there is no network call at scan time.

Skarn is licensed under the [Skarn End User License Agreement](https://getskarn.com/terms/?utm_source=action-readme&utm_medium=referral&utm_campaign=terms&utm_content=eula); running it constitutes acceptance. CI has no terminal to ask on, so Skarn prints a one-line stderr notice on each run instead (registering for the license already accepted the agreement on the form); set `SKARN_EULA_ACCEPTED: "1"` in the job's `env` to silence the notice on ephemeral runners.

A pull request from a fork cannot read repository secrets, so the license is empty there - on exactly the pull requests an open-source project most wants scanned. The Action does not fail that build: it emits a `::warning::`, writes a job-summary note explaining why, sets the `skipped` output to `true`, deletes any partial SARIF, and exits 0. The same scan runs on the base branch, where the secret is readable. Dependabot pull requests are treated the same way, because they run against Dependabot's own secrets store rather than the repository's Actions secrets.

Everywhere else, a missing license fails the job (exit 7) with a message that points at the free registration, never a bare exit code. Set `on-missing-license: warn` (or `soft-fail: true`) to downgrade that to a warning while a pipeline is still being wired up; fork and Dependabot pull requests are always skipped regardless of that input.

Guard the SARIF upload with `skipped` so no run that did not scan tries to upload a SARIF that was never written - this covers the fork/Dependabot skip and the `warn` / `soft-fail` paths alike, and it stops an empty run from telling GitHub code scanning that every alert is fixed:

```yaml
- name: Upload SARIF to code scanning
  if: always() && steps.skarn.outputs.skipped != 'true'
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: skarn-results.sarif
    category: skarn
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `skarn-path` | (empty) | Path to a pre-installed `skarn` binary. If set, or if `skarn` is already on `PATH`, the download step is skipped. |
| `version` | `latest` | Skarn version to download when no binary is on `PATH`. Pin a concrete version (for example `0.15.0`); `latest` is rejected because there is no version to resolve without a network lookup. |
| `download-base-url` | skarn-dist releases | Base URL the binary is fetched from: `<base>/v<version>/skarn-<arch>-<os>`. Checksums are always fetched from the canonical `skarn-dist` release, never from this URL; a fetch that fails against a custom base falls back to the canonical GitHub URL once. |
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
| `license` | (empty) | Skarn license token, exported as `SKARN_LICENSE`. `skarn check` needs one; the free license is issued at https://getskarn.com/free?utm_source=action-readme&utm_medium=referral&utm_campaign=free&utm_content=license-input after a quick email confirmation. Pass it from a repository secret. |
| `on-missing-license` | `fail` | When `check` finds no license (exit 7) outside a fork or Dependabot pull request: `fail` the job, or `warn` and pass. Fork and Dependabot pull requests are always warned and skipped regardless. |
| `extra-args` | (empty) | Additional arguments appended to the `skarn check` invocation, split on whitespace (quoted values with spaces are not preserved). |

## Outputs

| Output | Description |
| --- | --- |
| `sarif-file` | Path to the written SARIF report. |
| `exit-code` | The `skarn check` exit code (0 clean, 1 fail-on-severity, 2 fail-on-risk, 3 canary, 5 paid feature not covered, 6 scan error, 7 no license installed). |
| `risk-score` | Session risk score (0-100) parsed from the SARIF report. |
| `findings-count` | Number of findings in the SARIF report. |
| `skipped` | `true` whenever `check` found no license and did not scan, so no SARIF was written (a fork/Dependabot PR, or `on-missing-license: warn` / `soft-fail`, or a hard failure); `false` on any run that scanned. It reports whether a SARIF exists to upload, not whether the job passed. Guard a SARIF upload with `if: always() && steps.<id>.outputs.skipped != 'true'`. |

## Binary acquisition

The Action ships only this config and a thin wrapper; it never embeds the binary or any non-public rules. It resolves `skarn` in order: an explicit `skarn-path`, then `skarn` on `PATH`, then a download of the pinned `version` from `download-base-url`. Point `skarn-path` at a binary you install in an earlier step, or pin `version` once the public release channel is live. `skarn check` needs a license (see [Skarn license](#skarn-license)); the free one is issued after a quick email confirmation, and fork pull requests where the secret is unreadable are skipped rather than failed.

The download branch verifies every binary it fetches. It downloads the pinned `skarn-<arch>-<os>` asset, then fetches `SHA256SUMS` from the canonical `skarn-dist` release for that version and checks the asset's sha256 against it, failing closed with a clear error on any mismatch, missing checksum line, or missing `SHA256SUMS` asset - the downloaded file is deleted before a later step could run it. The checksums always come from the canonical release, never from `download-base-url`, so a custom mirror can never vouch for its own bytes; if a fetch from a custom `download-base-url` fails, the Action logs a notice and retries the canonical GitHub URL once. This defeats a compromised `download-base-url` mirror and transit corruption, but not compromise of the canonical release assets themselves - an attacker who controls the `skarn-dist` release controls both the binary and its `SHA256SUMS`. Verifying the binary against the signed `SHA256SUMS.sigstore.json` cosign bundle out of band is the recorded follow-up that closes that gap. `SHA256SUMS` ships from v0.19.0 onward: pinning an earlier `version` fails closed because those releases predate it, so pin v0.19.0 or newer - or, for a supply-chain-sensitive pipeline, install `skarn` in an earlier step with your own verification (the OCI image is cosign-signed with an SBOM) and pass `skarn-path`.

## What appears where

Findings live in AI-session files under `$HOME`, not in your repository tree, so the SARIF result locations point at session file paths rather than repo lines. GitHub code scanning ingests the SARIF and lists the findings in the Security tab, but it cannot anchor them to a pull-request diff line (there is no matching source line). The always-on job summary and workflow annotations are therefore the primary developer-facing surface; the SARIF upload is the durable Security-tab record and cross-run dedupe (via `partialFingerprints`).

## Runner support

The wrapper is a Bash composite step: Linux and macOS runners are supported. Windows runners are not (`skarn.exe` and `skarn guard` still work directly; only this Action's wrapper is Bash-only).

## Real-time alternative

This Action is the batch, after-the-fact path. For real-time, pre-execution blocking inside an agent, use `skarn guard` (a hook that vets each tool call before it runs). See the plugin integrations under `integrations/`. For the GitHub Copilot cloud agent specifically, `integrations/copilot-cloud-agent/` gates each tool call server-side before it runs, in the same CI this Action scans after the fact.

## License

This Action - the `action.yml` manifest, the wrapper scripts, and these docs - is released under the MIT License (see `LICENSE`). It ships configuration and a thin wrapper only. The `skarn` binary it downloads and runs is proprietary software, licensed separately; see https://getskarn.com/?utm_source=action-readme&utm_medium=referral&utm_campaign=home&utm_content=license-footer and the license distributed with the binary.
