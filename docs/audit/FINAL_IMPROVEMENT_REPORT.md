# Final improvement report

Status: implementation complete locally; public Action release update remains
the final publishing operation.

## Before

The Action was an inline Bash composite with a flat two-state check list. It
used the closing synchronous SBOM export endpoint, labelled permission/API
failures as `not_configured`, had no declared outputs or tests, failed the
whole step on optional sync errors and offered no working ForgeVault CTA. See
[`BEFORE_IMPROVEMENT.md`](BEFORE_IMPROVEMENT.md).

## After

- `action/action.yml` is concise Marketplace metadata with `shield` / `blue`
  branding, declared outputs, minimal inputs and a separate runner script.
- `action/run.sh` implements a canonical `CheckResult` shape with six explicit
  statuses, bounded HTTP calls and grouped Job Summary output.
- Security policy, SBOM, Dependency Graph, dependency monitoring, Code
  Scanning, security contact, product mapping and incident owner are checked
  with deterministic evidence and one remediation each.
- The Action remains informational by default; `fail-on` is opt-in.
- `readiness.json` includes `schema_version`, action/run metadata, check
  evidence and count summaries without a legal compliance boolean.

## Deprecated API migration

The production Action no longer uses the deprecated synchronous
`/dependency-graph/sbom` export. It uses the documented asynchronous
`generate-report` → `fetch-report` flow, handles `201`, `202`, `302`, `403`,
`404` and service failures, and bounds polling to seconds rather than minutes.
The compatibility record is in [`GITHUB_API_COMPATIBILITY.md`](../GITHUB_API_COMPATIBILITY.md).

## Detection accuracy

`DETECTED`, `NOT_DETECTED`, `NOT_AVAILABLE`, `NOT_AUTHORIZED`, `UNKNOWN` and
`ERROR` are kept distinct. Missing permission, a plan limitation, an API outage
and missing evidence no longer become the same result.

## Privacy changes

The default path sends zero requests to ForgeVault. Optional sync is validated,
token-authenticated, versioned and sanitized. The sync endpoint now accepts the
canonical result model and persists unknown/error counts separately. A sync
failure leaves the local report available.

## Job Summary and funnel

The summary now includes repository, timestamp, Action version, grouped result
tables, counts, next steps, privacy state, a concise legal limitation and a
clickable ForgeVault Pro link with privacy-safe UTM parameters. The README now
explains the free/pro boundary, minimum permissions, results, troubleshooting,
privacy and limitations in the first viewport.

## Tests added

`tests/action/test-run.sh` covers:

- asynchronous SBOM ready (`201` → `202` → `302`);
- SBOM processing timeout (`UNKNOWN`);
- `403` authorization handling;
- static absence of the deprecated endpoint;
- `sync=false` zero ForgeVault requests;
- sanitized successful sync;
- ForgeVault outage without local-result failure;
- token redaction and Job Summary CTA;
- opt-in `fail-on=gap` behavior.

Fixture-based self-dogfood is defined in `action/.github/workflows/action-test.yml`.

## Runtime and performance

The runner uses only Bash, curl and jq. HTTP requests have timeouts and one
bounded retry. SBOM polling defaults to ten seconds with a one-second interval;
independent checks avoid broad repository scans. No runtime package install or
Node bundle is required.

## Commercial and Marketplace changes

- Marketplace copy is centralized in [`MARKETPLACE_COPY.md`](../MARKETPLACE_COPY.md).
- Primary category remains Security; secondary category remains Reporting.
- The real production CTA is `https://forge-vault-self.vercel.app` with only
  acquisition UTM parameters.
- Competitor positioning is documented in [`COMPETITOR_POSITIONING.md`](COMPETITOR_POSITIONING.md).
- The next compatible release is `v1.1.0`; existing `@v1` usage remains the
  stable major path.

## Remaining limitations

- Repository checks are not a legal CRA determination and do not establish
  product scope, reportability or statutory deadlines.
- Dependency monitoring is detected from the reviewed Dependabot configuration;
  the Action does not manage Dependabot alerts.
- A local SBOM does not, by itself, prove that GitHub Dependency Graph is
  available; the report shows that distinction.
- GitHub plan differences, fork permissions and API outages can produce
  `NOT_AVAILABLE`, `NOT_AUTHORIZED` or `UNKNOWN`.
- One manual operation is required to publish the updated public release:
  upload the changed Action files to `danny134/forge-vault-action`, create
  `v1.1.0`, move the compatible `v1` tag to the reviewed release commit and
  confirm Security / Reporting Marketplace metadata. No legal agreement is
  accepted by the automation.

## Definition of done

The local Action implementation, docs and tests satisfy the technical and
commercial requirements. The public Marketplace listing is considered fully
updated only after the release checklist is completed and the rendered page
shows the new metadata and README.
