# Privacy and sync contract

ForgeVault CRA Readiness is private by default. The Action runs in the GitHub
Actions runner and does not send a request to ForgeVault when `sync: false`.

## What the local Action reads

The Action reads only these known paths after `actions/checkout`:

- `SECURITY.md` and `.github/SECURITY.md`;
- `sbom.spdx.json`, `sbom.cyclonedx.json` and `sbom.json` at the repository root;
- `.github/dependabot.yml` and `.github/dependabot.yaml`;
- `.github/workflows/*.yml` and `.github/workflows/*.yaml` for CodeQL or
  code-scanning references;
- `.forgevault.yml` and `.forgevault.yaml` for product and incident-owner keys.

It does not archive the repository, scan arbitrary source files or upload any
of these files to ForgeVault.

## GitHub API calls

When no local evidence is available and the job has a valid GitHub context, the
Action may call:

- `GET /repos/{owner}/{repo}/contents/SECURITY.md` and the `.github` variant;
- `GET /repos/{owner}/{repo}/dependency-graph/sbom/generate-report`;
- `GET /repos/{owner}/{repo}/dependency-graph/sbom/fetch-report/{uuid}`;
- the short-lived HTTPS `Location` returned for a completed SBOM, without the
  GitHub authorization header;
- `GET /repos/{owner}/{repo}/code-scanning/alerts?per_page=1` when no local
  Code Scanning workflow is detected.

The SBOM flow is bounded and uses GitHub's asynchronous API. A downloaded SBOM
is validated in a temporary runner file and is never forwarded to ForgeVault.

## `sync: false`

Zero requests are sent to the ForgeVault endpoint. The Action writes a local
`readiness.json` report with the check results and GitHub run metadata.

## `sync: true`

Sync is permitted only when the workflow explicitly supplies `sync: true`, a
ForgeVault action token and a product identifier. The POST body is the
versioned, sanitized `readiness.json` report:

```json
{
  "schema_version": "1",
  "action_version": "1.1.0",
  "observed_at": "2026-09-04T12:00:00Z",
  "repository": "owner/repository",
  "commit_sha": "...",
  "run_id": "123",
  "run_attempt": "1",
  "product": "northstar-desktop-agent",
  "idempotency_key": "owner/repository:123:1:northstar-desktop-agent",
  "checks": [
    {
      "id": "security-policy",
      "title": "Security policy",
      "group": "product-security",
      "status": "DETECTED",
      "summary": "...",
      "evidence": "...",
      "source": "workspace",
      "remediation": "...",
      "docs_url": "https://..."
    }
  ],
  "summary": {
    "detected": 1,
    "gaps": 0,
    "unknown": 0,
    "errors": 0
  }
}
```

The actual report contains one object per supported check. The following are
never sent by the Action:

- source code or repository archives;
- SBOM contents or raw dependency lists;
- secrets or GitHub tokens;
- commit bodies, pull-request descriptions or arbitrary files;
- analytics identifiers or private repository identifiers in the CTA URL.

The ForgeVault ingestion endpoint stores only a bounded sanitized summary. It
stores a SHA-256 hash of the action token, not the token itself. A sync outage
or invalid optional sync configuration produces a warning while preserving the
local readiness result.

## CTA tracking

The Job Summary links to the current ForgeVault deployment with only:

`utm_source=github&utm_medium=marketplace_action&utm_campaign=cra_readiness`

No repository name, product identifier or security finding is placed in that
URL. The current production URL is centralized in the Action as
`https://forge-vault-self.vercel.app`, matching the deployment record in
`docs/DEPLOYMENT.md`.
