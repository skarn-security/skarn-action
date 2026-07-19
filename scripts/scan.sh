#!/usr/bin/env bash
set -euo pipefail

log() { printf 'skarn-action: %s\n' "$1" >&2; }
fail() { log "$1"; exit 1; }

resolve_binary() {
  if [ -n "${INPUT_SKARN_PATH:-}" ]; then
    [ -x "$INPUT_SKARN_PATH" ] || fail "skarn-path '$INPUT_SKARN_PATH' is not an executable file"
    printf '%s' "$INPUT_SKARN_PATH"
    return
  fi
  if command -v skarn >/dev/null 2>&1; then
    command -v skarn
    return
  fi

  local os arch uname_s uname_m
  uname_s=$(uname -s)
  uname_m=$(uname -m)
  case "$uname_s" in
    Linux) os=linux ;;
    Darwin) os=macos ;;
    *) fail "unsupported runner OS '$uname_s'; provide skarn-path or install skarn on PATH" ;;
  esac
  case "$uname_m" in
    x86_64 | amd64) arch=x86_64 ;;
    arm64 | aarch64) arch=aarch64 ;;
    *) fail "unsupported runner architecture '$uname_m'" ;;
  esac

  local ver="${INPUT_VERSION:-latest}"
  [ "$ver" = "latest" ] && fail "no skarn on PATH and version is 'latest'; pin a concrete version (for example 0.15.0) or set skarn-path"
  ver="${ver#v}"

  local url dest
  url="${INPUT_DOWNLOAD_BASE_URL%/}/v${ver}/skarn-${arch}-${os}"
  dest="${RUNNER_TEMP:-/tmp}/skarn"
  log "downloading skarn ${ver} from ${url}"
  curl -fsSL --retry 3 -o "$dest" "$url" || fail "download failed from ${url}"
  chmod +x "$dest"
  printf '%s' "$dest"
}

BIN=$(resolve_binary)
log "using $("$BIN" --version 2>/dev/null || echo skarn)"

SARIF_FILE="${INPUT_SARIF_FILE:-skarn-results.sarif}"

ARGS=(check --format sarif)
[ -n "${INPUT_HOURS:-}" ] && ARGS+=(--hours "$INPUT_HOURS")
[ -n "${INPUT_CLI:-}" ] && ARGS+=(--cli "$INPUT_CLI")
[ -n "${INPUT_PROJECT:-}" ] && ARGS+=(--project "$INPUT_PROJECT")
[ -n "${INPUT_SEVERITY:-}" ] && ARGS+=(--severity "$INPUT_SEVERITY")
[ -n "${INPUT_FAIL_ON_SEVERITY:-}" ] && ARGS+=(--fail-on-severity "$INPUT_FAIL_ON_SEVERITY")
[ -n "${INPUT_FAIL_ON_RISK:-}" ] && ARGS+=(--fail-on-risk "$INPUT_FAIL_ON_RISK")
if [ -n "${INPUT_EXTRA_ARGS:-}" ]; then
  read -r -a extra <<<"$INPUT_EXTRA_ARGS"
  ARGS+=("${extra[@]}")
fi

log "running: skarn ${ARGS[*]}"
set +e
"$BIN" "${ARGS[@]}" >"$SARIF_FILE"
CODE=$?
set -e

if [ "$CODE" = "7" ]; then
  license_skip=false
  skip_reason=""
  if [ "${GITHUB_ACTOR:-}" = "dependabot[bot]" ]; then
    license_skip=true
    skip_reason=dependabot
  elif [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ] && [ -f "${GITHUB_EVENT_PATH:-}" ]; then
    HEAD_REPO=$(jq -r '.pull_request.head.repo.full_name // ""' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "")
    if [ -n "$HEAD_REPO" ] && [ "$HEAD_REPO" != "${GITHUB_REPOSITORY:-}" ]; then
      license_skip=true
      skip_reason=fork
    fi
  fi

  rm -f "$SARIF_FILE"

  if [ "$license_skip" = "true" ]; then
    if [ "$skip_reason" = "dependabot" ]; then
      skip_msg="A Dependabot pull request runs against Dependabot's own secrets store, so this repository's Actions secrets - including the Skarn license - were not available, and the AI-session scan did not run. This is expected and it is not a failure: the same scan runs on the base branch, where the secret is readable."
    else
      skip_msg="A pull request from a fork cannot read this repository's secrets, so the Skarn license was not available and the AI-session scan did not run. This is expected and it is not a failure: the same scan runs on the base branch, where the secret is readable. Nothing was blocked and nothing was suppressed."
    fi
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      {
        echo "## Skarn AI-session scan skipped"
        echo
        echo "Skarn skipped this pull request. $skip_msg"
      } >>"$GITHUB_STEP_SUMMARY"
    fi
    printf '::warning title=Skarn scan skipped::%s\n' "Skarn skipped this pull request. $skip_msg"
    {
      echo "skipped=true"
      echo "exit-code=$CODE"
    } >>"${GITHUB_OUTPUT:-/dev/null}"
    log "no license available on this pull request ($skip_reason); skipping the scan without failing the job"
    exit 0
  fi

  # shellcheck disable=SC2016
  no_license_summary='Skarn did not scan: no license was found. `skarn check` needs a license, and the free one is issued at https://getskarn.com/free after a quick email confirmation. Add it as a repository secret and pass it: `with: { license: ${{ secrets.SKARN_LICENSE }} }`.'
  # shellcheck disable=SC2016
  no_license_note='No license found. skarn check needs a license; the free one is issued at https://getskarn.com/free after a quick email confirmation. Add it as a repository secret and pass license: ${{ secrets.SKARN_LICENSE }}.'
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "## Skarn AI-session scan"
      echo
      echo "$no_license_summary"
    } >>"$GITHUB_STEP_SUMMARY"
  fi
  {
    echo "skipped=true"
    echo "exit-code=$CODE"
  } >>"${GITHUB_OUTPUT:-/dev/null}"
  if [ "${INPUT_SOFT_FAIL:-false}" = "true" ] || [ "${INPUT_ON_MISSING_LICENSE:-fail}" = "warn" ]; then
    printf '::warning title=Skarn::%s\n' "$no_license_note"
    log "no license found; soft-fail or on-missing-license=warn is set, not failing the job"
    exit 0
  fi
  printf '::error title=Skarn::%s\n' "$no_license_note"
  log "no license found; skarn check needs one - register free at https://getskarn.com/free (exit $CODE)"
  exit "$CODE"
fi

if ! jq empty "$SARIF_FILE" >/dev/null 2>&1; then
  cat "$SARIF_FILE" >&2 || true
  fail "skarn check did not produce valid SARIF (exit ${CODE})"
fi

RESULTS="${RUNNER_TEMP:-/tmp}/skarn-results.json"
jq '[.runs[0].results[] | select(has("suppressions") | not)]' "$SARIF_FILE" >"$RESULTS"

RISK=$(jq -r '.runs[0].properties.riskScore // 0' "$SARIF_FILE")
SESSIONS=$(jq -r '.runs[0].properties.sessionsScanned // 0' "$SARIF_FILE")
COUNT=$(jq -r 'length' "$RESULTS")
ERRORS=$(jq -r '[.[] | select(.level == "error")] | length' "$RESULTS")
WARNINGS=$(jq -r '[.[] | select(.level == "warning")] | length' "$RESULTS")
NOTES=$(jq -r '[.[] | select(.level == "note")] | length' "$RESULTS")

{
  echo "sarif-file=$SARIF_FILE"
  echo "exit-code=$CODE"
  echo "risk-score=$RISK"
  echo "findings-count=$COUNT"
  echo "skipped=false"
} >>"${GITHUB_OUTPUT:-/dev/null}"

if [ "${INPUT_JOB_SUMMARY:-true}" = "true" ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Skarn AI-session scan"
    echo
    echo "Scanned **${SESSIONS}** AI coding-assistant session(s). Risk score **${RISK}/100**."
    echo
    echo "| Severity | Findings |"
    echo "| --- | --- |"
    echo "| error (high/critical) | ${ERRORS} |"
    echo "| warning (medium) | ${WARNINGS} |"
    echo "| note (low) | ${NOTES} |"
    echo
    if [ "$COUNT" -gt 0 ]; then
      SUMMARY_CAP=100
      echo "| Level | Rule | Finding | Session |"
      echo "| --- | --- | --- | --- |"
      jq -r --argjson cap "$SUMMARY_CAP" '
        .[:$cap][]
        | [.level, .ruleId, (.message.text | gsub("[|\r\n\t]"; " ")), (.locations[0].physicalLocation.artifactLocation.uri // "")]
        | @tsv' "$RESULTS" |
        while IFS=$'\t' read -r level rule msg uri; do
          echo "| ${level} | ${rule} | ${msg} | \`${uri##*/}\` |"
        done
      if [ "$COUNT" -gt "$SUMMARY_CAP" ]; then
        echo
        echo "_Showing the first ${SUMMARY_CAP} of ${COUNT} findings; the full set is in the SARIF report (\`${SARIF_FILE}\`)._"
      fi
    else
      echo "No findings."
    fi
  } >>"$GITHUB_STEP_SUMMARY"
fi

if [ "${INPUT_ANNOTATIONS:-true}" = "true" ] && [ "$COUNT" -gt 0 ]; then
  ANNOTATE_CAP=50
  emitted=0
  while IFS=$'\t' read -r level rule msg; do
    if [ "$emitted" -ge "$ANNOTATE_CAP" ]; then
      log "annotation cap ${ANNOTATE_CAP} reached; $((COUNT - ANNOTATE_CAP)) further finding(s) are in the SARIF report and job summary only"
      break
    fi
    case "$level" in
      error) cmd=error ;;
      warning) cmd=warning ;;
      *) cmd=notice ;;
    esac
    printf '::%s title=Skarn %s::%s\n' "$cmd" "$rule" "$msg"
    emitted=$((emitted + 1))
  done < <(jq -r '.[] | [.level, .ruleId, (.message.text | gsub("[\r\n]"; " ") | gsub("::"; ":"))] | @tsv' "$RESULTS")
fi

log "risk ${RISK}/100, ${COUNT} finding(s) (${ERRORS} error, ${WARNINGS} warning, ${NOTES} note); SARIF at ${SARIF_FILE}"

if [ "${INPUT_SOFT_FAIL:-false}" = "true" ]; then
  log "soft-fail is on; not failing the job (scan exit code ${CODE})"
  exit 0
fi
exit "$CODE"
