#!/usr/bin/env bash

set -euo pipefail

# ForgeVault CRA Readiness is intentionally a small, dependency-free composite
# action. It uses only the runner's bash, curl and jq; it never runs npm install
# and it never uploads repository files to ForgeVault.

readonly ACTION_VERSION='1.1.0'
readonly SCHEMA_VERSION='1'
readonly FORGEVAULT_APP_URL_DEFAULT='https://forge-vault-self.vercel.app'
readonly GITHUB_API_VERSION='2026-03-10'
readonly DEFAULT_HTTP_TIMEOUT_SECONDS='12'
readonly DEFAULT_SBOM_MAX_WAIT_SECONDS='10'
readonly DEFAULT_SBOM_POLL_INTERVAL_SECONDS='1'

GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
GITHUB_API_ROOT="${GITHUB_API_URL:-https://api.github.com}"
GITHUB_API_ROOT="${GITHUB_API_ROOT%/}"
REPOSITORY="${GITHUB_REPOSITORY:-}"
WORKSPACE="${GITHUB_WORKSPACE:-$PWD}"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-}"
OUTPUT_FILE="${GITHUB_OUTPUT:-}"
FORGEVAULT_APP_URL="${FORGEVAULT_APP_URL:-$FORGEVAULT_APP_URL_DEFAULT}"
HTTP_TIMEOUT_SECONDS="${FORGEVAULT_HTTP_TIMEOUT_SECONDS:-$DEFAULT_HTTP_TIMEOUT_SECONDS}"
SBOM_MAX_WAIT_SECONDS="${FORGEVAULT_SBOM_MAX_WAIT_SECONDS:-$DEFAULT_SBOM_MAX_WAIT_SECONDS}"
SBOM_POLL_INTERVAL_SECONDS="${FORGEVAULT_SBOM_POLL_INTERVAL_SECONDS:-$DEFAULT_SBOM_POLL_INTERVAL_SECONDS}"
SYNC_INPUT="${FORGEVAULT_SYNC:-false}"
FAIL_ON="${FORGEVAULT_FAIL_ON:-none}"

if ! command -v jq >/dev/null 2>&1; then
  echo '::error::ForgeVault CRA Readiness requires jq on the runner.'
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo '::error::ForgeVault CRA Readiness requires curl on the runner.'
  exit 1
fi

case "$SYNC_INPUT" in
  true|TRUE|True|false|FALSE|False) ;;
  *)
    echo '::error::sync must be true or false.'
    exit 1
    ;;
esac

case "$FAIL_ON" in
  none|error|gap|unknown) ;;
  *)
    echo '::error::fail-on must be one of none, error, gap, or unknown.'
    exit 1
    ;;
esac

if ! printf '%s' "$HTTP_TIMEOUT_SECONDS" | grep -Eq '^[0-9]+$'; then
  echo '::error::FORGEVAULT_HTTP_TIMEOUT_SECONDS must be a positive integer.'
  exit 1
fi

if ! printf '%s' "$SBOM_MAX_WAIT_SECONDS" | grep -Eq '^[0-9]+$'; then
  echo '::error::FORGEVAULT_SBOM_MAX_WAIT_SECONDS must be a non-negative integer.'
  exit 1
fi

if ! printf '%s' "$SBOM_POLL_INTERVAL_SECONDS" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then
  echo '::error::FORGEVAULT_SBOM_POLL_INTERVAL_SECONDS must be a non-negative number.'
  exit 1
fi

if ! TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/forge-vault-action.XXXXXX" 2>/dev/null)"; then
  TMP_DIR="$(mktemp -d -t forge-vault-action)"
fi
trap 'rm -rf "$TMP_DIR"' EXIT

if [ -z "$SUMMARY_FILE" ]; then
  SUMMARY_FILE="$TMP_DIR/summary.md"
fi

if [ -n "$GH_TOKEN" ]; then
  GH_CURL_CONFIG="$TMP_DIR/github-curl.conf"
  printf 'header = "Authorization: Bearer %s"\n' "$GH_TOKEN" > "$GH_CURL_CONFIG"
  printf 'header = "Accept: application/vnd.github+json"\n' >> "$GH_CURL_CONFIG"
  printf 'header = "X-GitHub-Api-Version: %s"\n' "$GITHUB_API_VERSION" >> "$GH_CURL_CONFIG"
  chmod 600 "$GH_CURL_CONFIG"
else
  GH_CURL_CONFIG=''
fi

if [ "${GITHUB_ACTIONS:-false}" = 'true' ]; then
  if [ -n "${FORGEVAULT_TOKEN:-}" ]; then
    printf '::add-mask::%s\n' "$FORGEVAULT_TOKEN"
  fi
  if [ -n "$GH_TOKEN" ]; then
    printf '::add-mask::%s\n' "$GH_TOKEN"
  fi
fi

if [ -d "$WORKSPACE" ]; then
  HAS_WORKSPACE='true'
else
  HAS_WORKSPACE='false'
fi

if [ -d "$WORKSPACE/.git" ]; then
  HAS_CHECKOUT='true'
else
  HAS_CHECKOUT='false'
fi

if printf '%s' "$REPOSITORY" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
  VALID_REPOSITORY='true'
else
  VALID_REPOSITORY='false'
fi

SUMMARY_LINES=0
summary_line() {
  printf '%s\n' "$1" >> "$SUMMARY_FILE"
  SUMMARY_LINES=$((SUMMARY_LINES + 1))
}

CHECK_STATUS='UNKNOWN'
CHECK_SUMMARY=''
CHECK_EVIDENCE=''
CHECK_SOURCE=''
CHECK_REMEDIATION=''
CHECK_DOCS_URL=''

set_result() {
  CHECK_STATUS="$1"
  CHECK_SUMMARY="$2"
  CHECK_EVIDENCE="$3"
  CHECK_SOURCE="$4"
  CHECK_REMEDIATION="$5"
  CHECK_DOCS_URL="$6"
}

API_STATUS=''
API_BODY=''
API_HEADERS=''
API_LOCATION=''
API_SEQUENCE=0

api_get() {
  local url="$1"
  local status_file
  local error_file
  local curl_exit

  API_SEQUENCE=$((API_SEQUENCE + 1))
  API_BODY="$TMP_DIR/api-body-${API_SEQUENCE}.json"
  API_HEADERS="$TMP_DIR/api-headers-${API_SEQUENCE}.txt"
  status_file="$TMP_DIR/api-status-${API_SEQUENCE}.txt"
  error_file="$TMP_DIR/api-error-${API_SEQUENCE}.txt"
  API_STATUS=''
  API_LOCATION=''

  set +e
  if [ -n "$GH_CURL_CONFIG" ]; then
    curl --silent --show-error --max-time "$HTTP_TIMEOUT_SECONDS" \
      --retry 1 --retry-delay 1 --retry-max-time "$HTTP_TIMEOUT_SECONDS" \
      --config "$GH_CURL_CONFIG" \
      --dump-header "$API_HEADERS" --output "$API_BODY" \
      --write-out '%{http_code}' "$url" > "$status_file" 2> "$error_file"
  else
    curl --silent --show-error --max-time "$HTTP_TIMEOUT_SECONDS" \
      --retry 1 --retry-delay 1 --retry-max-time "$HTTP_TIMEOUT_SECONDS" \
      --header 'Accept: application/vnd.github+json' \
      --header "X-GitHub-Api-Version: ${GITHUB_API_VERSION}" \
      --dump-header "$API_HEADERS" --output "$API_BODY" \
      --write-out '%{http_code}' "$url" > "$status_file" 2> "$error_file"
  fi
  curl_exit=$?
  set -e

  if [ "$curl_exit" -ne 0 ]; then
    return 1
  fi

  API_STATUS="$(tr -d '\r\n' < "$status_file")"
  API_LOCATION="$(awk 'tolower($1) == "location:" { sub(/\r$/, "", $0); sub(/^[^:]*:[[:space:]]*/, "", $0); print; exit }' "$API_HEADERS")"
  return 0
}

download_url() {
  local url="$1"
  local status_file="$TMP_DIR/download-status.txt"
  local error_file="$TMP_DIR/download-error.txt"
  local curl_exit

  DOWNLOAD_BODY="$TMP_DIR/sbom-download.json"
  DOWNLOAD_STATUS=''

  case "$url" in
    https://*) ;;
    *) return 1 ;;
  esac

  set +e
  curl --silent --show-error --max-time "$HTTP_TIMEOUT_SECONDS" \
    --retry 1 --retry-delay 1 --retry-max-time "$HTTP_TIMEOUT_SECONDS" \
    --dump-header "$TMP_DIR/download-headers.txt" --output "$DOWNLOAD_BODY" \
    --write-out '%{http_code}' "$url" > "$status_file" 2> "$error_file"
  curl_exit=$?
  set -e

  if [ "$curl_exit" -ne 0 ]; then
    return 1
  fi
  DOWNLOAD_STATUS="$(tr -d '\r\n' < "$status_file")"
  return 0
}

github_file_url() {
  printf '%s/repos/%s/contents/%s' "$GITHUB_API_ROOT" "$REPOSITORY" "$1"
}

status_label() {
  case "$1" in
    DETECTED) printf '✓ Detected' ;;
    NOT_DETECTED) printf '⚠ Not detected' ;;
    NOT_AVAILABLE) printf '○ Not available' ;;
    NOT_AUTHORIZED) printf '? Not authorized' ;;
    UNKNOWN) printf '? Unable to verify' ;;
    ERROR) printf '✕ Error' ;;
    *) printf '? Unknown state' ;;
  esac
}

CHECKS_JSON='[]'
CHECK_COUNT=0
DETECTED_COUNT=0
GAP_COUNT=0
UNKNOWN_COUNT=0
ERROR_COUNT=0

record_check() {
  local id="$1"
  local title="$2"
  local group="$3"
  local check_function="$4"

  "$check_function"
  CHECK_COUNT=$((CHECK_COUNT + 1))
  case "$CHECK_STATUS" in
    DETECTED) DETECTED_COUNT=$((DETECTED_COUNT + 1)) ;;
    NOT_DETECTED) GAP_COUNT=$((GAP_COUNT + 1)) ;;
    NOT_AVAILABLE|NOT_AUTHORIZED|UNKNOWN) UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1)) ;;
    ERROR) ERROR_COUNT=$((ERROR_COUNT + 1)) ;;
  esac

  CHECKS_JSON="$(jq -c \
    --arg id "$id" \
    --arg title "$title" \
    --arg group "$group" \
    --arg status "$CHECK_STATUS" \
    --arg summary "$CHECK_SUMMARY" \
    --arg evidence "$CHECK_EVIDENCE" \
    --arg source "$CHECK_SOURCE" \
    --arg remediation "$CHECK_REMEDIATION" \
    --arg docs_url "$CHECK_DOCS_URL" \
    '. + [{id: $id, title: $title, group: $group, status: $status, summary: $summary, evidence: $evidence, source: $source, remediation: $remediation, docs_url: $docs_url}]' \
    <<< "$CHECKS_JSON")"
}

SECURITY_POLICY_STATUS='UNKNOWN'
SECURITY_POLICY_FILE=''

check_security_policy() {
  local candidate
  local api_path
  local saw_forbidden='false'
  local saw_unavailable='false'
  local saw_network='false'

  SECURITY_POLICY_FILE=''
  if [ -f "$WORKSPACE/SECURITY.md" ]; then
    SECURITY_POLICY_FILE="$WORKSPACE/SECURITY.md"
    SECURITY_POLICY_STATUS='DETECTED'
    set_result 'DETECTED' 'A SECURITY.md policy is present in the checked-out repository.' 'SECURITY.md' 'workspace' 'Keep the policy current and use a private reporting route for vulnerabilities.' 'https://docs.github.com/en/repositories/creating-and-managing-repositories/defining-the-community-profile-for-your-repository/adding-a-security-policy-to-your-repository'
    return 0
  fi
  if [ -f "$WORKSPACE/.github/SECURITY.md" ]; then
    SECURITY_POLICY_FILE="$WORKSPACE/.github/SECURITY.md"
    SECURITY_POLICY_STATUS='DETECTED'
    set_result 'DETECTED' 'A .github/SECURITY.md policy is present in the checked-out repository.' '.github/SECURITY.md' 'workspace' 'Keep the policy current and use a private reporting route for vulnerabilities.' 'https://docs.github.com/en/repositories/creating-and-managing-repositories/defining-the-community-profile-for-your-repository/adding-a-security-policy-to-your-repository'
    return 0
  fi

  if [ "$HAS_CHECKOUT" = 'true' ] && [ -z "$GH_TOKEN" ]; then
    SECURITY_POLICY_STATUS='NOT_DETECTED'
    set_result 'NOT_DETECTED' 'No SECURITY.md policy was found in the checked-out repository.' 'Checked SECURITY.md and .github/SECURITY.md' 'workspace' 'Add SECURITY.md or .github/SECURITY.md with a private vulnerability-reporting route.' 'https://docs.github.com/en/repositories/creating-and-managing-repositories/defining-the-community-profile-for-your-repository/adding-a-security-policy-to-your-repository'
    return 0
  fi

  if [ "$VALID_REPOSITORY" != 'true' ] || [ -z "$GH_TOKEN" ]; then
    SECURITY_POLICY_STATUS='UNKNOWN'
    set_result 'UNKNOWN' 'Repository contents were not available locally and no usable GitHub API context was present.' 'No local checkout or authenticated contents request' 'runner' 'Run actions/checkout before this Action and grant contents: read.' 'https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#permissions'
    return 0
  fi

  for candidate in SECURITY.md .github/SECURITY.md; do
    api_path="$(github_file_url "$candidate")"
    if ! api_get "$api_path"; then
      saw_network='true'
      continue
    fi
    case "$API_STATUS" in
      200)
        SECURITY_POLICY_STATUS='DETECTED'
        set_result 'DETECTED' "GitHub reports $candidate is present." "$candidate via GitHub Contents API" 'github-rest-api' 'Keep the policy current and use a private vulnerability-reporting route.' 'https://docs.github.com/en/rest/repos/contents#get-repository-content'
        return 0
        ;;
      403) saw_forbidden='true' ;;
      5*) saw_unavailable='true' ;;
      404) ;;
      *) saw_network='true' ;;
    esac
  done

  if [ "$saw_forbidden" = 'true' ]; then
    SECURITY_POLICY_STATUS='NOT_AUTHORIZED'
    set_result 'NOT_AUTHORIZED' 'GitHub denied access to repository contents with the current token.' 'Contents API returned 403' 'github-rest-api' 'Grant contents: read or run the Action after actions/checkout.' 'https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#permissions'
  elif [ "$saw_unavailable" = 'true' ]; then
    SECURITY_POLICY_STATUS='NOT_AVAILABLE'
    set_result 'NOT_AVAILABLE' 'GitHub did not make repository contents available for this check.' 'Contents API returned a service-unavailable response' 'github-rest-api' 'Retry the workflow; repository feature availability can vary by GitHub plan or service state.' 'https://docs.github.com/en/rest/repos/contents#get-repository-content'
  elif [ "$saw_network" = 'true' ]; then
    SECURITY_POLICY_STATUS='UNKNOWN'
    set_result 'UNKNOWN' 'The security policy could not be verified because GitHub did not respond.' 'Contents API request did not complete' 'github-rest-api' 'Retry the workflow and inspect GitHub API availability.' 'https://www.githubstatus.com/'
  else
    SECURITY_POLICY_STATUS='NOT_DETECTED'
    set_result 'NOT_DETECTED' 'GitHub did not report SECURITY.md or .github/SECURITY.md.' 'Contents API returned 404 for both supported paths' 'github-rest-api' 'Add SECURITY.md or .github/SECURITY.md with a private vulnerability-reporting route.' 'https://docs.github.com/en/repositories/creating-and-managing-repositories/defining-the-community-profile-for-your-repository/adding-a-security-policy-to-your-repository'
  fi
  return 0
}

SBOM_STATUS='UNKNOWN'
SBOM_SOURCE=''
SBOM_EVIDENCE=''

set_sbom_result() {
  set_result "$1" "$2" "$3" "$4" "$5" "$6"
  SBOM_STATUS="$CHECK_STATUS"
  SBOM_SOURCE="$CHECK_SOURCE"
  SBOM_EVIDENCE="$CHECK_EVIDENCE"
}

check_sbom() {
  local candidate
  local generate_url
  local fetch_url
  local sbom_url
  local now
  local deadline

  SBOM_STATUS='UNKNOWN'
  SBOM_SOURCE=''
  SBOM_EVIDENCE=''

  for candidate in sbom.spdx.json sbom.cyclonedx.json sbom.json; do
    if [ -f "$WORKSPACE/$candidate" ]; then
      if jq -e 'type == "object" and ((.spdxVersion? != null) or (.bomFormat? != null))' "$WORKSPACE/$candidate" >/dev/null 2>&1; then
        set_sbom_result 'DETECTED' "A valid SBOM artifact is present at $candidate." "$candidate in the checked-out repository" 'workspace' 'Keep the SBOM generated from the shipped artifact or dependency graph and review it as part of release evidence.' 'https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/exporting-a-software-bill-of-materials-for-your-repository'
      else
        set_sbom_result 'ERROR' "An SBOM file exists at $candidate but is not valid SPDX or CycloneDX JSON." "$candidate failed the minimal format check" 'workspace' 'Regenerate the SBOM as SPDX JSON or CycloneDX JSON and rerun the workflow.' 'https://spdx.dev/specifications/'
      fi
      return 0
    fi
  done

  if [ "$VALID_REPOSITORY" != 'true' ] || [ -z "$GH_TOKEN" ]; then
    set_sbom_result 'UNKNOWN' 'No local SBOM was found and the asynchronous GitHub SBOM API could not be called.' 'Requires a checkout or contents: read token for the GitHub SBOM API' 'runner' 'Run actions/checkout and grant contents: read so GitHub can be queried without uploading source code.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
    return 0
  fi

  generate_url="$GITHUB_API_ROOT/repos/$REPOSITORY/dependency-graph/sbom/generate-report"
  if ! api_get "$generate_url"; then
    set_sbom_result 'UNKNOWN' 'The GitHub SBOM generation request did not complete.' 'Asynchronous SBOM generation request failed before an HTTP response' 'github-rest-api' 'Retry the workflow and inspect GitHub API availability.' 'https://www.githubstatus.com/'
    return 0
  fi

  case "$API_STATUS" in
    403)
      set_sbom_result 'NOT_AUTHORIZED' 'GitHub denied the SBOM generation request with the current token.' 'generate-report returned 403' 'github-rest-api' 'Grant contents: read to the job token and ensure the repository Dependency Graph is available.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
      return 0
      ;;
    404)
      set_sbom_result 'NOT_AVAILABLE' 'GitHub does not expose asynchronous SBOM generation for this repository.' 'generate-report returned 404' 'github-rest-api' 'Enable the Dependency Graph where supported, or provide a reviewed SBOM artifact.' 'https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/enabling-the-dependency-graph'
      return 0
      ;;
    5*)
      set_sbom_result 'UNKNOWN' 'GitHub SBOM generation could not be verified because GitHub returned a temporary server error.' "generate-report returned $API_STATUS" 'github-rest-api' 'Retry the workflow after GitHub API availability is restored.' 'https://www.githubstatus.com/'
      return 0
      ;;
    201) ;;
    *)
      set_sbom_result 'ERROR' 'GitHub returned an unexpected response while requesting the SBOM.' "generate-report returned $API_STATUS" 'github-rest-api' 'Inspect the GitHub API response and rerun the workflow.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
      return 0
      ;;
  esac

  sbom_url="$(jq -r '.sbom_url // empty' "$API_BODY" 2>/dev/null || true)"
  if [ -z "$sbom_url" ]; then
    set_sbom_result 'ERROR' 'GitHub accepted SBOM generation but did not return a report URL.' '201 response did not contain sbom_url' 'github-rest-api' 'Retry the workflow and report an unexpected GitHub API response if it persists.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
    return 0
  fi

  case "$sbom_url" in
    "$GITHUB_API_ROOT/repos/$REPOSITORY/dependency-graph/sbom/fetch-report/"*)
      fetch_url="$sbom_url"
      ;;
    "/repos/$REPOSITORY/dependency-graph/sbom/fetch-report/"*)
      fetch_url="$GITHUB_API_ROOT$sbom_url"
      ;;
    *)
      set_sbom_result 'ERROR' 'GitHub returned an unexpected SBOM report URL.' 'Report URL was outside the expected GitHub API path' 'github-rest-api' 'Retry the workflow and report an unexpected GitHub API response if it persists.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
      return 0
      ;;
  esac

  deadline=$(( $(date +%s) + SBOM_MAX_WAIT_SECONDS ))
  while :; do
    if ! api_get "$fetch_url"; then
      set_sbom_result 'UNKNOWN' 'The generated SBOM could not be fetched because GitHub did not respond.' 'fetch-report request did not complete' 'github-rest-api' 'Retry the workflow; the report may still be processing.' 'https://www.githubstatus.com/'
      return 0
    fi

    case "$API_STATUS" in
      202)
        now="$(date +%s)"
        if [ "$now" -ge "$deadline" ]; then
          set_sbom_result 'UNKNOWN' 'GitHub was still processing the SBOM when the Action timeout was reached.' "fetch-report returned 202 for ${SBOM_MAX_WAIT_SECONDS}s" 'github-rest-api' 'Rerun the workflow; GitHub may finish generating the report between runs.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
          return 0
        fi
        sleep "$SBOM_POLL_INTERVAL_SECONDS"
        ;;
      302)
        if [ -z "$API_LOCATION" ]; then
          set_sbom_result 'ERROR' 'GitHub reported a completed SBOM without a download location.' 'fetch-report returned 302 without Location' 'github-rest-api' 'Retry the workflow and report an unexpected GitHub API response if it persists.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
          return 0
        fi
        if ! download_url "$API_LOCATION"; then
          set_sbom_result 'UNKNOWN' 'The temporary SBOM download URL could not be reached.' 'Temporary SBOM download request did not complete' 'github-rest-api' 'Retry the workflow; the temporary URL is short-lived.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
          return 0
        fi
        if [ "$DOWNLOAD_STATUS" != '200' ]; then
        case "$DOWNLOAD_STATUS" in 403) set_sbom_result 'NOT_AUTHORIZED' 'GitHub denied access to the temporary SBOM download.' 'Temporary download returned 403' 'github-rest-api' 'Grant contents: read to the job token and retry.' 'https://docs.github.com/en/rest/dependency-graph/sboms' ;; 404) set_sbom_result 'NOT_AVAILABLE' 'GitHub generated the report but its temporary download is no longer available.' 'Temporary download returned 404' 'github-rest-api' 'Request a fresh report by rerunning the workflow.' 'https://docs.github.com/en/rest/dependency-graph/sboms' ;; 5*) set_sbom_result 'UNKNOWN' 'The temporary SBOM download could not be verified because GitHub returned a temporary server error.' "temporary SBOM download returned $DOWNLOAD_STATUS" 'github-rest-api' 'Retry the workflow to request a fresh SBOM report.' 'https://www.githubstatus.com/' ;; *) set_sbom_result 'ERROR' 'GitHub returned an unexpected response for the temporary SBOM download.' "temporary SBOM download returned $DOWNLOAD_STATUS" 'github-rest-api' 'Inspect the GitHub API response and rerun the workflow.' 'https://docs.github.com/en/rest/dependency-graph/sboms' ;; esac
          return 0
        fi
        if jq -e 'type == "object" and ((.spdxVersion? != null) or (.bomFormat? != null))' "$DOWNLOAD_BODY" >/dev/null 2>&1; then
          set_sbom_result 'DETECTED' 'GitHub generated an SPDX-compatible SBOM successfully.' 'Asynchronous generate-report → fetch-report → temporary download completed' 'github-rest-api' 'Review the SBOM as release evidence; this Action does not upload its contents to ForgeVault.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
        else
          set_sbom_result 'ERROR' 'GitHub returned a completed SBOM that did not pass the minimal format check.' 'Temporary download was not SPDX or CycloneDX JSON' 'github-rest-api' 'Inspect the generated report and rerun the workflow.' 'https://spdx.dev/specifications/'
        fi
        return 0
        ;;
      403)
        set_sbom_result 'NOT_AUTHORIZED' 'GitHub denied access while fetching the generated SBOM.' 'fetch-report returned 403' 'github-rest-api' 'Grant contents: read to the job token and retry.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
        return 0
        ;;
      404)
        set_sbom_result 'NOT_AVAILABLE' 'GitHub no longer had the requested SBOM report.' 'fetch-report returned 404' 'github-rest-api' 'Request a fresh report by rerunning the workflow.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
        return 0
        ;;
      5*)
        set_sbom_result 'UNKNOWN' 'GitHub SBOM retrieval could not be verified because GitHub returned a temporary server error.' "fetch-report returned $API_STATUS" 'github-rest-api' 'Retry the workflow after GitHub API availability is restored.' 'https://www.githubstatus.com/'
        return 0
        ;;
      *)
        set_sbom_result 'ERROR' 'GitHub returned an unexpected response while fetching the SBOM.' "fetch-report returned $API_STATUS" 'github-rest-api' 'Inspect the GitHub API response and rerun the workflow.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
        return 0
        ;;
    esac
  done
}

check_dependency_graph() {
  case "$SBOM_SOURCE" in
    github-rest-api)
      if [ "$SBOM_STATUS" = 'DETECTED' ]; then
        set_result 'DETECTED' 'GitHub Dependency Graph evidence was available through the asynchronous SBOM flow.' "$SBOM_EVIDENCE" 'github-rest-api' 'Keep the Dependency Graph enabled and review generated SBOM evidence as part of release operations.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
      else
        set_result "$SBOM_STATUS" 'GitHub Dependency Graph could not be positively verified in this run.' "$SBOM_EVIDENCE" 'github-rest-api' 'Retry the workflow or resolve the permission/availability state shown above.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
      fi
      ;;
    workspace)
      set_result 'UNKNOWN' 'A local SBOM was found, but that alone does not prove GitHub Dependency Graph availability.' "$SBOM_EVIDENCE" 'workspace' 'Grant contents: read so the asynchronous GitHub SBOM flow can be checked.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
      ;;
    *)
      set_result "$SBOM_STATUS" 'GitHub Dependency Graph could not be positively verified in this run.' "$SBOM_EVIDENCE" 'github-rest-api' 'Retry the workflow or resolve the permission/availability state shown above.' 'https://docs.github.com/en/rest/dependency-graph/sboms'
      ;;
  esac
  return 0
}

MAPPING_FILE=''

check_dependabot() {
  local candidate
  for candidate in .github/dependabot.yml .github/dependabot.yaml; do
    if [ -f "$WORKSPACE/$candidate" ]; then
      set_result 'DETECTED' "A Dependabot configuration is present at $candidate." "$candidate in the checked-out repository" 'workspace' 'Keep dependency monitoring enabled and review alerts in GitHub.' 'https://docs.github.com/en/code-security/dependabot/dependabot-alerts'
      return 0
    fi
  done
  if [ "$HAS_CHECKOUT" = 'true' ]; then
    set_result 'NOT_DETECTED' 'No Dependabot configuration file was found in the checked-out repository.' 'Checked .github/dependabot.yml and .github/dependabot.yaml' 'workspace' 'Add a reviewed .github/dependabot.yml or configure dependency monitoring in GitHub.' 'https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-dependency-updates'
  else
    set_result 'UNKNOWN' 'Dependabot configuration could not be checked because the repository was not checked out.' 'No local checkout available' 'runner' 'Run actions/checkout before this Action.' 'https://github.com/actions/checkout'
  fi
  return 0
}

check_code_scanning() {
  local workflow
  local alerts_url

  if [ -d "$WORKSPACE/.github/workflows" ]; then
    for workflow in "$WORKSPACE"/.github/workflows/*.yml "$WORKSPACE"/.github/workflows/*.yaml; do
      [ -f "$workflow" ] || continue
      if grep -Eiq 'github/codeql-action|codeql|code-scanning' "$workflow"; then
        set_result 'DETECTED' 'A CodeQL or code-scanning workflow is present.' "$(basename "$workflow")" 'workspace' 'Keep the workflow enabled and review alerts in GitHub.' 'https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning'
        return 0
      fi
    done
  fi

  if [ -z "$GH_TOKEN" ] || [ "$VALID_REPOSITORY" != 'true' ]; then
    if [ "$HAS_CHECKOUT" = 'true' ]; then
      set_result 'NOT_DETECTED' 'No CodeQL or code-scanning workflow was found in the checked-out repository.' 'Checked .github/workflows/*.yml and *.yaml' 'workspace' 'Add a reviewed CodeQL or code-scanning workflow if it fits your product-security process.' 'https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning'
    else
      set_result 'UNKNOWN' 'Code scanning could not be checked because the repository was not checked out and no API token was available.' 'No local workflow or authenticated API context' 'runner' 'Run actions/checkout and grant security-events: read for the API check.' 'https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#permissions'
    fi
    return 0
  fi

  alerts_url="$GITHUB_API_ROOT/repos/$REPOSITORY/code-scanning/alerts?per_page=1"
  if ! api_get "$alerts_url"; then
    set_result 'UNKNOWN' 'Code scanning could not be verified because GitHub did not respond.' 'Code Scanning alerts API request did not complete' 'github-rest-api' 'Retry the workflow and inspect GitHub API availability.' 'https://www.githubstatus.com/'
    return 0
  fi
  case "$API_STATUS" in
    200)
      set_result 'DETECTED' 'GitHub Code Scanning alerts are available to the current token.' 'Code Scanning alerts API returned 200' 'github-rest-api' 'Continue reviewing code-scanning findings in GitHub.' 'https://docs.github.com/en/rest/code-scanning/code-scanning'
      ;;
    403)
      set_result 'NOT_AUTHORIZED' 'Code scanning could not be checked with the current token permissions.' 'Code Scanning alerts API returned 403' 'github-rest-api' 'Grant security-events: read to the job or run after actions/checkout with a configured workflow.' 'https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#permissions'
      ;;
    404)
      set_result 'NOT_AVAILABLE' 'GitHub did not expose Code Scanning alerts for this repository.' 'Code Scanning alerts API returned 404' 'github-rest-api' 'Check whether Code Scanning is available for this repository and plan.' 'https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning'
      ;;
    5*)
      set_result 'NOT_AVAILABLE' 'GitHub Code Scanning was temporarily unavailable.' "Code Scanning alerts API returned $API_STATUS" 'github-rest-api' 'Retry the workflow after GitHub API availability is restored.' 'https://www.githubstatus.com/'
      ;;
    *)
      set_result 'ERROR' 'GitHub returned an unexpected response while checking Code Scanning.' "Code Scanning alerts API returned $API_STATUS" 'github-rest-api' 'Inspect the GitHub API response and rerun the workflow.' 'https://docs.github.com/en/rest/code-scanning/code-scanning'
      ;;
  esac
  return 0
}

check_security_contact() {
  if [ -n "$SECURITY_POLICY_FILE" ] && [ -f "$SECURITY_POLICY_FILE" ]; then
    if grep -Eiq 'security[[:space:]_-]*(contact|team)|security@|report[[:space:]]+(a[[:space:]]+)?vulnerabilit|security issue' "$SECURITY_POLICY_FILE"; then
      set_result 'DETECTED' 'The security policy contains a vulnerability-reporting route or security contact.' 'SECURITY.md content' 'workspace' 'Keep the reporting route private, monitored and current.' 'https://docs.github.com/en/code-security/security-advisories/working-with-repository-security-advisories/about-repository-security-advisories'
    else
      set_result 'NOT_DETECTED' 'A security policy exists but no clear reporting route was detected in its text.' 'SECURITY.md was readable; contact pattern was not found' 'workspace' 'Add concise instructions for privately reporting a vulnerability.' 'https://docs.github.com/en/repositories/creating-and-managing-repositories/defining-the-community-profile-for-your-repository/adding-a-security-policy-to-your-repository'
    fi
  elif [ "$SECURITY_POLICY_STATUS" = 'NOT_DETECTED' ]; then
    set_result 'NOT_DETECTED' 'No security policy was available from which to detect a reporting contact.' 'No SECURITY.md policy detected' 'workspace' 'Add SECURITY.md or .github/SECURITY.md with private reporting instructions.' 'https://docs.github.com/en/repositories/creating-and-managing-repositories/defining-the-community-profile-for-your-repository/adding-a-security-policy-to-your-repository'
  elif [ "$SECURITY_POLICY_STATUS" = 'NOT_AUTHORIZED' ]; then
    set_result 'NOT_AUTHORIZED' 'The security contact could not be checked because repository contents were not authorized.' 'Security policy contents were denied by GitHub' 'github-rest-api' 'Grant contents: read or run the Action after actions/checkout.' 'https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#permissions'
  elif [ "$SECURITY_POLICY_STATUS" = 'NOT_AVAILABLE' ]; then
    set_result 'NOT_AVAILABLE' 'The security contact could not be checked because repository contents were unavailable.' 'Security policy contents were unavailable from GitHub' 'github-rest-api' 'Retry the workflow after GitHub API availability is restored.' 'https://www.githubstatus.com/'
  else
    set_result 'UNKNOWN' 'The security contact could not be verified without readable policy contents.' 'Security policy contents were not available locally' 'github-rest-api' 'Run actions/checkout so the policy can be checked without reading unrelated files.' 'https://github.com/actions/checkout'
  fi
  return 0
}

check_product_mapping() {
  local candidate
  MAPPING_FILE=''
  for candidate in .forgevault.yml .forgevault.yaml; do
    if [ -f "$WORKSPACE/$candidate" ]; then
      MAPPING_FILE="$WORKSPACE/$candidate"
      if grep -Eiq '^[[:space:]]*(product|product_id|product-id):[[:space:]]*[^#[:space:]]' "$MAPPING_FILE"; then
        set_result 'DETECTED' "ForgeVault product mapping is declared in $candidate." "$candidate contains a product identifier" 'workspace' 'Keep the mapping identifier aligned with the product record in ForgeVault.' 'https://github.com/danny134/forge-vault-action#product-mapping'
      else
        set_result 'NOT_DETECTED' "$candidate exists but does not contain a product identifier." "$candidate was readable; product key was not detected" 'workspace' 'Add a product or product_id value to the reviewed ForgeVault mapping file.' 'https://github.com/danny134/forge-vault-action#product-mapping'
      fi
      return 0
    fi
  done
  if [ "$HAS_CHECKOUT" = 'true' ]; then
    set_result 'NOT_DETECTED' 'No ForgeVault product mapping file was found.' 'Checked .forgevault.yml and .forgevault.yaml' 'workspace' 'Add .forgevault.yml only if you want to connect this repository to a ForgeVault product workflow.' 'https://github.com/danny134/forge-vault-action#product-mapping'
  else
    set_result 'UNKNOWN' 'Product mapping could not be checked because the repository was not checked out.' 'No local checkout available' 'runner' 'Run actions/checkout before this Action.' 'https://github.com/actions/checkout'
  fi
  return 0
}

check_incident_owner() {
  if [ -z "$MAPPING_FILE" ] || [ ! -f "$MAPPING_FILE" ]; then
    if [ "$HAS_CHECKOUT" = 'true' ]; then
      set_result 'NOT_DETECTED' 'No ForgeVault mapping file with an operational incident owner was found.' 'No .forgevault.yml or .forgevault.yaml available' 'workspace' 'If this repository participates in ForgeVault operations, add an incident_owner value to the reviewed mapping file.' 'https://github.com/danny134/forge-vault-action#incident-owner'
    else
      set_result 'UNKNOWN' 'Incident ownership could not be checked because the repository was not checked out.' 'No local checkout available' 'runner' 'Run actions/checkout before this Action.' 'https://github.com/actions/checkout'
    fi
    return 0
  fi

  if grep -Eiq '^[[:space:]]*(incident_?owner|incident-owner|owner):[[:space:]]*[^#[:space:]]' "$MAPPING_FILE"; then
    set_result 'DETECTED' 'An operational incident owner is declared in the ForgeVault mapping.' "$(basename "$MAPPING_FILE") contains an incident owner" 'workspace' 'Keep the owner current and ensure the team has an escalation path.' 'https://github.com/danny134/forge-vault-action#incident-owner'
  else
    set_result 'NOT_DETECTED' 'The ForgeVault mapping does not declare an operational incident owner.' "$(basename "$MAPPING_FILE") contains no incident_owner or owner value" 'workspace' 'Add an incident_owner value for operational ownership; this is metadata, not a legal determination.' 'https://github.com/danny134/forge-vault-action#incident-owner'
  fi
  return 0
}

record_check 'security-policy' 'Security policy' 'product-security' check_security_policy
record_check 'sbom' 'SBOM availability' 'product-security' check_sbom
record_check 'dependency-graph' 'Dependency Graph' 'product-security' check_dependency_graph
record_check 'dependency-monitoring' 'Dependency monitoring configuration' 'product-security' check_dependabot
record_check 'code-scanning' 'Code scanning' 'product-security' check_code_scanning
record_check 'security-contact' 'Security contact' 'product-security' check_security_contact
record_check 'product-mapping' 'Product mapping' 'operational-readiness' check_product_mapping
record_check 'incident-owner' 'Incident owner' 'operational-readiness' check_incident_owner

OBSERVED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
RUN_ID="${GITHUB_RUN_ID:-}"
RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-}"
COMMIT_SHA="${GITHUB_SHA:-}"
PRODUCT_ID="${FORGEVAULT_PRODUCT:-}"
PRODUCT_ID="$(printf '%s' "$PRODUCT_ID" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

IDEMPOTENCY_KEY="${REPOSITORY}:${RUN_ID}:${RUN_ATTEMPT}:${PRODUCT_ID}"
if [ -z "$RUN_ID" ] && [ -n "$COMMIT_SHA" ]; then
  IDEMPOTENCY_KEY="${REPOSITORY}:${COMMIT_SHA}:${PRODUCT_ID}"
fi

REPORT_JSON="$(jq -c \
  --arg schema_version "$SCHEMA_VERSION" \
  --arg action_version "$ACTION_VERSION" \
  --arg observed_at "$OBSERVED_AT" \
  --arg repository "$REPOSITORY" \
  --arg commit_sha "$COMMIT_SHA" \
  --arg run_id "$RUN_ID" \
  --arg run_attempt "$RUN_ATTEMPT" \
  --arg product "$PRODUCT_ID" \
  --arg idempotency_key "$IDEMPOTENCY_KEY" \
  --argjson checks "$CHECKS_JSON" \
  --argjson detected "$DETECTED_COUNT" \
  --argjson gaps "$GAP_COUNT" \
  --argjson unknown "$UNKNOWN_COUNT" \
  --argjson errors "$ERROR_COUNT" \
  '{schema_version: $schema_version, action_version: $action_version, observed_at: $observed_at, repository: $repository, commit_sha: $commit_sha, run_id: $run_id, run_attempt: $run_attempt, product: $product, idempotency_key: $idempotency_key, checks: $checks, summary: {detected: $detected, gaps: $gaps, unknown: $unknown, errors: $errors}}' \
  <<< '{}')"

PAYLOAD_FILE="$TMP_DIR/readiness.json"
printf '%s\n' "$REPORT_JSON" > "$PAYLOAD_FILE"

if [ "$HAS_WORKSPACE" = 'true' ]; then
  if ! cp "$PAYLOAD_FILE" "$WORKSPACE/readiness.json" 2>/dev/null; then
    printf '::warning::Could not write readiness.json to the runner workspace; the report remains available through the Action output.\n'
  fi
fi

render_group() {
  local group="$1"
  local row_title
  local row_status
  local row_summary

  summary_line '| Check | Status | Evidence |'
  summary_line '| --- | --- | --- |'
  while IFS="$(printf '\t')" read -r row_title row_status row_summary; do
    [ -n "$row_title" ] || continue
    summary_line "| $row_title | $(status_label "$row_status") | $row_summary |"
  done <<EOF
$(jq -r --arg group "$group" '.[] | select(.group == $group) | [.title, .status, .summary] | @tsv' <<< "$CHECKS_JSON")
EOF
  summary_line ''
}

summary_line '# ForgeVault CRA Readiness'
summary_line ''
summary_line '> Cyber Resilience Act readiness checks for GitHub repositories.'
summary_line ''
summary_line '## Run'
summary_line ''
summary_line "- **Repository:** \`${REPOSITORY:-unavailable}\`"
summary_line "- **Observed:** \`${OBSERVED_AT}\`"
summary_line "- **Action version:** \`v${ACTION_VERSION}\`"
summary_line ''
summary_line '## Product security'
summary_line ''
render_group 'product-security'
summary_line '## Operational readiness'
summary_line ''
render_group 'operational-readiness'
summary_line '## Result'
summary_line ''
summary_line "- **${DETECTED_COUNT} checks detected.**"
summary_line "- **${GAP_COUNT} operational gaps.**"
summary_line "- **${UNKNOWN_COUNT} checks could not be verified.**"
if [ "$ERROR_COUNT" -gt 0 ]; then
  summary_line "- **${ERROR_COUNT} technical errors.**"
fi
summary_line ''

if [ "$GAP_COUNT" -gt 0 ] || [ "$UNKNOWN_COUNT" -gt 0 ] || [ "$ERROR_COUNT" -gt 0 ]; then
  summary_line '### Next steps'
  summary_line ''
  while IFS="$(printf '\t')" read -r row_title row_status row_remediation row_docs_url; do
    [ -n "$row_title" ] || continue
    summary_line "- **$row_title — $(status_label "$row_status")** $row_remediation ([details]($row_docs_url))"
  done <<EOF
$(jq -r '.[] | select(.status != "DETECTED") | [.title, .status, .remediation, .docs_url] | @tsv' <<< "$CHECKS_JSON")
EOF
  summary_line ''
fi

SYNC_INPUT_LOWER="$(printf '%s' "$SYNC_INPUT" | tr '[:upper:]' '[:lower:]')"
SYNC_STATE='not-requested'
SYNC_STATUS=''

if [ "$SYNC_INPUT_LOWER" = 'true' ]; then
  if [ -z "$FORGEVAULT_TOKEN" ]; then
    SYNC_STATE='not-configured'
    printf '::warning::sync=true was requested but no ForgeVault token was provided. Local readiness completed; no SaaS request was sent.\n'
  elif ! printf '%s' "$FORGEVAULT_TOKEN" | grep -Eiq '^fv_[0-9a-f]{64}$'; then
    SYNC_STATE='not-configured'
    printf '::warning::sync=true was requested but the ForgeVault token format is invalid. Local readiness completed; no SaaS request was sent.\n'
  elif [ -z "$PRODUCT_ID" ]; then
    SYNC_STATE='not-configured'
    printf '::warning::sync=true was requested but no product identifier was provided. Local readiness completed; no SaaS request was sent.\n'
  elif [ "${#PRODUCT_ID}" -gt 160 ] || ! printf '%s' "$PRODUCT_ID" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
    SYNC_STATE='not-configured'
    printf '::warning::sync=true was requested but the product identifier is invalid. Local readiness completed; no SaaS request was sent.\n'
  elif [ -z "${FORGEVAULT_ENDPOINT:-}" ]; then
    SYNC_STATE='not-configured'
    printf '::warning::sync=true was requested but no ForgeVault endpoint was provided. Local readiness completed; no SaaS request was sent.\n'
  elif ! printf '%s' "${FORGEVAULT_ENDPOINT}" | grep -Eq '^https://[^[:space:]]+$'; then
    SYNC_STATE='not-configured'
    printf '::warning::sync=true was requested but the ForgeVault endpoint is not an HTTPS URL. Local readiness completed; no SaaS request was sent.\n'
  else
    SYNC_CONFIG="$TMP_DIR/sync-curl.conf"
    printf 'header = "Authorization: Bearer %s"\n' "$FORGEVAULT_TOKEN" > "$SYNC_CONFIG"
    printf 'header = "Content-Type: application/json"\n' >> "$SYNC_CONFIG"
    chmod 600 "$SYNC_CONFIG"
    SYNC_STATUS_FILE="$TMP_DIR/sync-status.txt"
    SYNC_ERROR_FILE="$TMP_DIR/sync-error.txt"
    set +e
    curl --silent --show-error --max-time 15 \
      --retry 1 --retry-delay 1 --retry-max-time 15 \
      --config "$SYNC_CONFIG" --request POST \
      --data-binary @"$PAYLOAD_FILE" --output "$TMP_DIR/sync-response.txt" \
      --write-out '%{http_code}' "${FORGEVAULT_ENDPOINT}" > "$SYNC_STATUS_FILE" 2> "$SYNC_ERROR_FILE"
    SYNC_EXIT=$?
    set -e
    if [ "$SYNC_EXIT" -eq 0 ]; then
      SYNC_STATUS="$(tr -d '\r\n' < "$SYNC_STATUS_FILE")"
    fi
    case "$SYNC_STATUS" in
      2*)
        SYNC_STATE='synced'
        ;;
      *)
        SYNC_STATE='failed'
        printf '::warning::ForgeVault synchronization failed%s. Local readiness completed and remains available.\n' "$(if [ -n "$SYNC_STATUS" ]; then printf ' with HTTP %s' "$SYNC_STATUS"; fi)"
        ;;
    esac
  fi
fi

summary_line '## Privacy and ForgeVault sync'
summary_line ''
if [ "$SYNC_STATE" = 'not-requested' ]; then
  summary_line '> **Private by default:** no request was sent to ForgeVault. The checks ran in GitHub Actions only.'
elif [ "$SYNC_STATE" = 'synced' ]; then
  summary_line '> A sanitized readiness summary was sent to ForgeVault because `sync: true` was explicitly enabled. Source code, secrets and raw dependency data were not uploaded.'
elif [ "$SYNC_STATE" = 'failed' ]; then
  summary_line '> Local readiness completed, but the optional ForgeVault synchronization failed. No source code or raw dependency data was sent.'
else
  summary_line '> Local readiness completed, but the optional sync was not configured. No request was sent to ForgeVault.'
fi
summary_line ''
summary_line '## Go beyond repository readiness'
summary_line ''
summary_line 'ForgeVault Pro connects repositories to software products and adds security-signal assessment, 24h/72h CRA case workflows, engineering evidence timelines, reporting preparation and immutable case history.'
summary_line ''
summary_line "[Open ForgeVault Pro →](${FORGEVAULT_APP_URL%/}/?utm_source=github&utm_medium=marketplace_action&utm_campaign=cra_readiness)"
summary_line ''
summary_line '> ForgeVault CRA Readiness detects technical and operational signals. It does not determine legal CRA applicability, reportability or compliance.'

if [ -n "$OUTPUT_FILE" ]; then
  printf 'detected-count=%s\n' "$DETECTED_COUNT" >> "$OUTPUT_FILE"
  printf 'gap-count=%s\n' "$GAP_COUNT" >> "$OUTPUT_FILE"
  printf 'unknown-count=%s\n' "$UNKNOWN_COUNT" >> "$OUTPUT_FILE"
  printf 'report-json=%s\n' "$REPORT_JSON" >> "$OUTPUT_FILE"
fi

case "$FAIL_ON" in
  none) exit 0 ;;
  error)
    if [ "$ERROR_COUNT" -gt 0 ]; then exit 1; fi
    ;;
  gap)
    if [ "$ERROR_COUNT" -gt 0 ] || [ "$GAP_COUNT" -gt 0 ]; then exit 1; fi
    ;;
  unknown)
    if [ "$ERROR_COUNT" -gt 0 ] || [ "$UNKNOWN_COUNT" -gt 0 ]; then exit 1; fi
    ;;
esac

exit 0
