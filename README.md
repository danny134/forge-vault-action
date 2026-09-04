# ForgeVault CRA Readiness

> Cyber Resilience Act readiness checks for GitHub repositories.

**Private by default:** the check runs inside GitHub Actions. No source code is
uploaded to ForgeVault unless you explicitly enable the optional SaaS sync.

[![GitHub Marketplace](https://img.shields.io/badge/GitHub%20Marketplace-ForgeVault%20CRA%20Readiness-2088FF?logo=github)](https://github.com/marketplace/actions/forgevault-cra-readiness)
[![Latest release](https://img.shields.io/github/v/release/danny134/forge-vault-action?sort=semver)](https://github.com/danny134/forge-vault-action/releases)
[![License](https://img.shields.io/github/license/danny134/forge-vault-action)](LICENSE)

## What it does

ForgeVault CRA Readiness gives engineering and product-security teams a fast,
repository-level view of evidence that supports Cyber Resilience Act readiness.
It detects operational signals in the checked-out repository and, where
permission allows, uses GitHub's read-only APIs. It does not determine whether
a product is legally in scope or compliant with the CRA.

The free Action is the repository entry point to [ForgeVault Pro](https://forge-vault-self.vercel.app/?utm_source=github&utm_medium=marketplace_action&utm_campaign=cra_readiness), where teams can connect repositories to software products and manage evidence and human-reviewed CRA workflows.

## Example result

```text
FORGEVAULT CRA READINESS

Repository  acme/desktop-agent
Action      v1.1.0

Product security
✓ Security policy       Detected
✓ SBOM availability     Detected
? Code scanning         Unable to verify with current token permissions

Operational readiness
⚠ Product mapping       Not detected
✓ Incident owner        Detected

Result
5 checks detected · 1 operational gap · 1 could not be verified

This is a readiness report, not a legal compliance determination.
```

## Checks

The Action uses one canonical result model for every check:

| Status           | Meaning                                                                   |
| ---------------- | ------------------------------------------------------------------------- |
| `DETECTED`       | Positive evidence was found.                                              |
| `NOT_DETECTED`   | The check ran successfully but found no supported evidence.               |
| `NOT_AVAILABLE`  | GitHub does not expose the feature in this repository or plan.            |
| `NOT_AUTHORIZED` | The current token does not have the permission needed to check it.        |
| `UNKNOWN`        | The result could not be determined, for example because an API timed out. |
| `ERROR`          | An unexpected technical error occurred.                                   |

Supported signals are security policy, SBOM availability, Dependency Graph,
Dependabot configuration, Code Scanning, a security contact, ForgeVault product
mapping and an operational incident owner. Each result includes evidence,
source, one next step and a documentation link in `readiness.json`.

### Product mapping

If a repository belongs to a ForgeVault product workflow, add a small reviewed
`.forgevault.yml` or `.forgevault.yaml` file with a `product` or `product_id`
value. This is ForgeVault operational metadata, not a legal CRA requirement.

### Incident owner

The same mapping file may declare `incident_owner` (or `owner`) so the team can
see who owns the operational follow-up. This is a workflow signal, not a legal
determination.

## Quick start

The Action expects the repository to be checked out first. The workflow below
requests only read permissions and does not create issues, pull requests or
commits.

```yaml
name: CRA readiness

on:
  workflow_dispatch:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  security-events: read

jobs:
  readiness:
    runs-on: ubuntu-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@v6

      - name: Run ForgeVault CRA Readiness
        uses: danny134/forge-vault-action@v1
```

`security-events: read` lets the Action distinguish a missing Code Scanning
signal from a token that cannot query Code Scanning. If it is unavailable in a
forked pull request, the result is `NOT_AUTHORIZED`; the local readiness report
still completes.

## Required permissions

| API or local signal                    | Minimum permission                           | Why                                                                  |
| -------------------------------------- | -------------------------------------------- | -------------------------------------------------------------------- |
| Checked-out files                      | `contents: read` for `actions/checkout`      | Reads only the known policy, workflow, mapping and SBOM paths.       |
| Asynchronous SBOM generation and fetch | `contents: read`                             | Requests and polls GitHub's current SBOM flow.                       |
| Code Scanning alerts fallback          | `security-events: read`                      | Distinguishes API access from a missing Code Scanning result.        |
| Optional ForgeVault sync               | A ForgeVault action token in a GitHub Secret | Sends only the documented sanitized summary when explicitly enabled. |

No write permission is required. See the full [token permission map](docs/GITHUB_TOKEN_PERMISSIONS.md).

## Understanding the results

The GitHub Job Summary groups checks into Product security and Operational
readiness. It reports counts, not a legal or compliance percentage:

- `Detected` means the Action observed the stated evidence.
- `Not detected` means the check was available and found no supported evidence.
- `Not available` means GitHub did not expose the feature in this context.
- `Not authorized` means the job token needs permission for that API.
- `Unable to verify` means the Action needs a retry or more context.
- `Error` means an unexpected technical failure needs investigation.

Each non-detected result has one concise remediation. By default, readiness
gaps do not fail the workflow. Use `fail-on` only when the team wants a gate.

## Privacy

With the default `sync: false`:

- the Action runs in the GitHub-hosted or self-hosted runner;
- no request is sent to ForgeVault infrastructure;
- it does not archive the repository or upload source code;
- it does not upload SBOM contents, raw dependency lists, commit bodies or pull-request contents;
- it writes a local `readiness.json` report containing check results and GitHub run metadata.

The Action reads only the known paths described in the [privacy and sync
contract](docs/PRIVACY_AND_SYNC.md). GitHub API responses are used for the
local result and are never forwarded to ForgeVault by default.

## Optional ForgeVault sync

Sync is opt-in and sends a sanitized readiness summary only when all of these
are supplied:

```yaml
- name: Sync readiness to ForgeVault
  uses: danny134/forge-vault-action@v1
  with:
    sync: true
    token: ${{ secrets.FORGEVAULT_TOKEN }}
    product: northstar-desktop-agent
```

The token is created in ForgeVault under **Settings → GitHub Action**, shown
once, stored as a hash and revocable by a workspace administrator. A sync
failure produces a warning but does not discard the local readiness result.
The endpoint override is intended only for an approved ForgeVault deployment;
the default is the current production ingestion endpoint.

See the exact payload in [PRIVACY_AND_SYNC.md](docs/PRIVACY_AND_SYNC.md).

## ForgeVault Pro

### From repository readiness to CRA operations

The free Action provides useful repository evidence. ForgeVault Pro operates at
the product level:

| Free Action                         | ForgeVault Pro                            |
| ----------------------------------- | ----------------------------------------- |
| Repository checks                   | Product mapping across repositories       |
| Local, private-by-default execution | Security signal assessment                |
| GitHub Job Summary                  | Human-reviewed CRA case workflows         |
| Basic remediation guidance          | Evidence timelines and report preparation |
| Optional sanitized sync             | Immutable incident and audit history      |

Need product-level CRA operations? [Open ForgeVault Pro →](https://forge-vault-self.vercel.app/?utm_source=github&utm_medium=marketplace_action&utm_campaign=cra_readiness)

The free Action does not start a statutory clock, decide reportability or submit
anything to ENISA. Those decisions stay with the manufacturer and the team's
human review process.

## Inputs

| Input      | Required | Default                       | Description                                                             |
| ---------- | -------- | ----------------------------- | ----------------------------------------------------------------------- |
| `sync`     | No       | `false`                       | Explicitly enable sanitized ForgeVault synchronization.                 |
| `token`    | No       | —                             | ForgeVault action token, used only with `sync: true`.                   |
| `endpoint` | No       | Production ingestion endpoint | Approved ForgeVault ingestion endpoint override.                        |
| `product`  | No       | —                             | ForgeVault product identifier for an opt-in sync.                       |
| `fail-on`  | No       | `none`                        | `none`, `error`, `gap` or `unknown`; controls optional workflow gating. |

## Outputs

| Output           | Description                                                      |
| ---------------- | ---------------------------------------------------------------- |
| `detected-count` | Number of checks with `DETECTED` evidence.                       |
| `gap-count`      | Number of `NOT_DETECTED` checks.                                 |
| `unknown-count`  | Number of `NOT_AVAILABLE`, `NOT_AUTHORIZED` or `UNKNOWN` checks. |
| `report-json`    | Compact machine-readable report with `schema_version`.           |

The local `readiness.json` file contains the same report for later workflow
steps. It does not include a `cra-compliant` boolean or a legal score.

## Troubleshooting

### SBOM is `UNKNOWN` or `NOT_AVAILABLE`

The Action uses GitHub's asynchronous `generate-report` → `fetch-report` flow,
waits only for a bounded interval and does not use the closing synchronous
endpoint. Retry the workflow if the report is still processing. A `403` is
`NOT_AUTHORIZED`; a `404` is `NOT_AVAILABLE`, not proof that an SBOM is missing.

### A check is `NOT_AUTHORIZED`

Review the job-level `permissions` block. For a pull request from a fork,
GitHub can restrict the token and secrets even when the base workflow requests
read access. The Action keeps that limitation visible rather than calling the
signal absent.

### Dependabot or Code Scanning is not detected

Dependabot detection checks the reviewed `.github/dependabot.yml` or
`.github/dependabot.yaml` configuration. Code Scanning first checks known
workflow files and otherwise queries the read-only alerts API when permitted.
GitHub plan and repository settings can change API availability.

### Sync is not working

Confirm `sync: true`, a current `FORGEVAULT_TOKEN` GitHub Secret and the exact
ForgeVault `product` identifier. The local report still completes if the SaaS
endpoint is unavailable. Never paste the token into a workflow log or issue.

## Security

Please use [GitHub private vulnerability reporting](SECURITY.md) for security
issues. Do not open a public issue with secrets, private repository data or
unreleased vulnerability details.

## Limitations

This Action checks repository-level technical and operational signals. It does
not inspect the whole repository, infer product scope, determine whether an
event is legally reportable, start a 24h/72h deadline, replace legal advice or
submit a regulatory report.

## Cyber Resilience Act disclaimer

> ForgeVault CRA Readiness detects technical and operational signals that may
> support Cyber Resilience Act readiness. It does not determine whether a
> product is in scope, whether an event is legally reportable, or whether an
> organization complies with the CRA.

## License

MIT. See [LICENSE](LICENSE).
