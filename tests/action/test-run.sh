#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -f "$ROOT/action/run.sh" ]; then
  ACTION_ROOT="$ROOT/action"
else
  ACTION_ROOT="$ROOT"
fi
ACTION="$ACTION_ROOT/run.sh"
FAKE_BIN="$ROOT/tests/action/fake-bin"
SYNC_TOKEN="fv_$(printf '%064d' 0)"

# GitHub's browser uploader stores test fixtures as regular files. Make the
# deterministic curl shim executable before putting it on PATH.
chmod +x "$FAKE_BIN/curl"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  if [ -n "${RUN_LOG:-}" ] && [ -f "$RUN_LOG" ]; then
    printf '%s\n' '--- action log ---' >&2
    sed -n '1,240p' "$RUN_LOG" >&2
  fi
  if [ -n "${RUN_SUMMARY:-}" ] && [ -f "$RUN_SUMMARY" ]; then
    printf '%s\n' '--- job summary ---' >&2
    sed -n '1,240p' "$RUN_SUMMARY" >&2
  fi
  exit 1
}

assert_eq() {
  if [ "$1" != "$2" ]; then
    fail "$3 (expected '$1', got '$2')"
  fi
}

assert_contains() {
  if ! grep -Fq "$1" "$2"; then
    fail "$3"
  fi
}

assert_not_contains() {
  if grep -Fq "$1" "$2"; then
    fail "$3"
  fi
}

run_case() {
  local fixture="$1"
  local mode="$2"
  local sync_input="${3:-false}"
  local case_dir
  local workspace
  local state_dir

  case_dir="$(mktemp -d "${TMPDIR:-/tmp}/forge-vault-action-test.XXXXXX")"
  workspace="$case_dir/workspace"
  state_dir="$case_dir/curl-state"
  mkdir -p "$workspace" "$state_dir"
  cp -R "$ROOT/tests/action/fixtures/$fixture/." "$workspace/"
  # Git does not version .git directories inside fixtures. Recreate the
  # checkout marker explicitly so the fixture exercises local repository
  # behavior both locally and in the public self-dogfood workflow.
  mkdir -p "$workspace/.git"

  RUN_SUMMARY="$case_dir/summary.md"
  RUN_OUTPUT="$case_dir/output.txt"
  RUN_LOG="$case_dir/action.log"
  RUN_REPORT="$workspace/readiness.json"
  RUN_CALLS="$state_dir/calls.log"

  # Leave enough whole-second headroom for a 202 -> 302 polling transition
  # when the test starts immediately before a clock tick on GitHub runners.
  set +e
  env \
    PATH="$FAKE_BIN:$PATH" \
    FAKE_CURL_MODE="$mode" \
    FAKE_CURL_STATE_DIR="$state_dir" \
    GITHUB_WORKSPACE="$workspace" \
    GITHUB_REPOSITORY='acme/good' \
    GITHUB_API_URL='https://api.github.test' \
    GITHUB_SHA='0123456789abcdef' \
    GITHUB_RUN_ID='1234' \
    GITHUB_RUN_ATTEMPT='1' \
    GITHUB_ACTIONS='false' \
    GITHUB_STEP_SUMMARY="$RUN_SUMMARY" \
    GITHUB_OUTPUT="$RUN_OUTPUT" \
    GH_TOKEN='fixture-github-token' \
    FORGEVAULT_SYNC="$sync_input" \
    FORGEVAULT_TOKEN="$SYNC_TOKEN" \
    FORGEVAULT_ENDPOINT='https://forge-vault.test/functions/v1/ingest-readiness' \
    FORGEVAULT_PRODUCT='northstar-desktop-agent' \
    FORGEVAULT_SBOM_MAX_WAIT_SECONDS='3' \
    FORGEVAULT_SBOM_POLL_INTERVAL_SECONDS='0' \
    FORGEVAULT_APP_URL='https://forge-vault-self.vercel.app' \
    bash "$ACTION" > "$RUN_LOG" 2>&1
  RUN_EXIT=$?
  set -e
}

report_status() {
  local id="$1"
  jq -r --arg id "$id" '.checks[] | select(.id == $id) | .status' "$RUN_REPORT"
}

report_count() {
  local key="$1"
  jq -r --arg key "$key" '.summary[$key]' "$RUN_REPORT"
}

if ! bash -n "$ACTION"; then
  fail 'action runner has invalid bash syntax'
fi

SCAN_PATHS=("$ACTION_ROOT")
if [ -d "$ROOT/supabase/functions" ]; then
  SCAN_PATHS+=("$ROOT/supabase/functions")
fi
if rg -n -e 'dependency-graph/sbom(["?[:space:]]|$)' \
  "${SCAN_PATHS[@]}" \
  --glob '*.sh' --glob '*.ts' --glob 'action.yml' >/dev/null 2>&1; then
  fail 'deprecated synchronous SBOM endpoint is present in production code'
fi

run_case good sbom_ready false
assert_eq '0' "$RUN_EXIT" 'ready fixture should succeed by default'
assert_eq 'DETECTED' "$(report_status sbom)" 'ready SBOM should be detected'
assert_eq 'DETECTED' "$(report_status dependency-graph)" 'ready dependency graph should be detected'
assert_eq '8' "$(report_count detected)" 'ready fixture detected count'
assert_eq '0' "$(report_count gaps)" 'ready fixture gap count'
assert_eq '0' "$(report_count unknown)" 'ready fixture unknown count'
assert_contains 'Cyber Resilience Act' "$RUN_SUMMARY" 'summary should expand CRA'
assert_contains 'Private by default' "$RUN_SUMMARY" 'summary should contain the trust statement'
assert_contains 'CRA Article 14 reporting obligations' "$RUN_SUMMARY" 'summary should contain the CRA timing context'
assert_contains 'Run a CRA incident drill in ForgeVault' "$RUN_SUMMARY" 'summary should contain the incident drill CTA'
assert_not_contains 'ingest-readiness' "$RUN_CALLS" 'sync=false must not call ForgeVault'

run_case minimal sbom_processing false
assert_eq '0' "$RUN_EXIT" 'processing state should be informational by default'
assert_eq 'UNKNOWN' "$(report_status sbom)" 'processing SBOM should be unknown'
assert_eq 'UNKNOWN' "$(report_status dependency-graph)" 'processing dependency graph should be unknown'
assert_not_contains 'not configured' "$RUN_SUMMARY" 'summary must not collapse states into not configured'

run_case restricted sbom_forbidden false
assert_eq '0' "$RUN_EXIT" 'forbidden checks should be informational by default'
assert_eq 'NOT_AUTHORIZED' "$(report_status security-policy)" 'policy 403 should be not authorized'
assert_eq 'NOT_AUTHORIZED' "$(report_status sbom)" 'SBOM 403 should be not authorized'
assert_eq 'NOT_AUTHORIZED' "$(report_status code-scanning)" 'code scanning 403 should be not authorized'
assert_contains 'Not authorized' "$RUN_SUMMARY" 'summary should name authorization limits'

run_case good sync_success true
assert_eq '0' "$RUN_EXIT" 'successful optional sync should succeed'
assert_contains 'ingest-readiness' "$RUN_CALLS" 'sync=true should call the configured ForgeVault endpoint'
assert_contains 'sanitized readiness summary was sent' "$RUN_SUMMARY" 'summary should describe the opt-in sync'
assert_not_contains "$SYNC_TOKEN" "$RUN_LOG" 'sync token must not appear in action logs'
assert_not_contains "$SYNC_TOKEN" "$RUN_SUMMARY" 'sync token must not appear in the job summary'
if ! jq -e '(.schema_version == "1") and (.checks | length == 8) and (has("dependencies") | not)' "$(dirname "$RUN_CALLS")/sync-body.json" >/dev/null; then
  fail 'sync payload must be versioned and sanitized'
fi

run_case good sync_fail true
assert_eq '0' "$RUN_EXIT" 'ForgeVault outage must not invalidate local readiness'
assert_contains 'synchronization failed' "$RUN_SUMMARY" 'summary should show a sync warning'
assert_contains 'Local readiness completed' "$RUN_SUMMARY" 'summary should preserve the local result'

run_case minimal sbom_unavailable false
assert_eq 'NOT_AVAILABLE' "$(report_status sbom)" 'SBOM 404 should be not available'
assert_eq 'NOT_AVAILABLE' "$(report_status dependency-graph)" 'dependency graph 404 should be not available'

run_case minimal sbom_server_error false
assert_eq 'UNKNOWN' "$(report_status sbom)" 'SBOM generation 5xx should be unknown'
assert_eq 'UNKNOWN' "$(report_status dependency-graph)" 'dependency graph generation 5xx should be unknown'

run_case minimal sbom_fetch_server_error false
assert_eq 'UNKNOWN' "$(report_status sbom)" 'SBOM fetch 5xx should be unknown'
assert_eq 'UNKNOWN' "$(report_status dependency-graph)" 'dependency graph fetch 5xx should be unknown'

run_case minimal sbom_download_server_error false
assert_eq 'UNKNOWN' "$(report_status sbom)" 'temporary SBOM download 5xx should be unknown'
assert_eq 'UNKNOWN' "$(report_status dependency-graph)" 'temporary download dependency graph 5xx should be unknown'

run_case minimal network_fail false
assert_eq 'UNKNOWN' "$(report_status sbom)" 'network failure should be unknown'
assert_eq 'UNKNOWN' "$(report_status security-policy)" 'security policy network failure should be unknown'

run_case minimal sbom_processing false
set +e
env \
  PATH="$FAKE_BIN:$PATH" \
  FAKE_CURL_MODE='sbom_processing' \
  FAKE_CURL_STATE_DIR="$(dirname "$RUN_CALLS")" \
  GITHUB_WORKSPACE="$(dirname "$RUN_REPORT")" \
  GITHUB_REPOSITORY='acme/good' \
  GITHUB_API_URL='https://api.github.test' \
  GITHUB_ACTIONS='false' \
  GITHUB_STEP_SUMMARY="$RUN_SUMMARY" \
  GH_TOKEN='' \
  FORGEVAULT_SYNC='false' \
  FORGEVAULT_FAIL_ON='gap' \
  FORGEVAULT_SBOM_MAX_WAIT_SECONDS='0' \
  FORGEVAULT_SBOM_POLL_INTERVAL_SECONDS='0' \
  bash "$ACTION" >/dev/null 2>&1
strict_exit=$?
set -e
assert_eq '1' "$strict_exit" 'fail-on=gap should fail when a gap is detected'

printf 'ForgeVault Action tests: PASS\n'
