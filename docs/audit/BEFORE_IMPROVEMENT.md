# Before improvement audit

Audit date: 2026-09-04

Scope: the free `ForgeVault CRA Readiness` Action in `action/`, before the
production-grade improvement pass. The public Marketplace repository at that
point was `danny134/forge-vault-action`, release `v1`.

## Feature set

The Action was a composite Bash Action that checked:

- `SECURITY.md` or `.github/SECURITY.md`;
- three root SBOM filenames;
- GitHub Dependency Graph through the SBOM REST API;
- `.github/dependabot.yml` or `.github/dependabot.yaml`;
- a CodeQL or code-scanning workflow;
- a security contact by recursively searching Markdown files;
- `.forgevault.yml` or `.forgevault.yaml` and a simple owner expression.

It wrote a small `readiness.json` file and a GitHub Job Summary. Optional SaaS
sync posted that file to the production `ingest-readiness` endpoint.

## Marketplace presentation

- Name: `ForgeVault CRA Readiness`.
- Description: `CRA product-security readiness check — security policy, SBOM,
dependency graph, incident owner. No exfiltration by default.`
- Branding: shield / blue.
- Marketplace categories: Security and Reporting.
- Public listing: <https://github.com/marketplace/actions/forgevault-cra-readiness>.
- Release strategy: a single public `v1` release and a moving major reference.

The README was concise but did not answer all first-viewport questions. It had no
real ForgeVault URL, no example output, no status semantics, no complete privacy
contract, no inputs/outputs table, no limitations section and no remediation
links.

## Detection logic and API calls

The old implementation used local shell predicates and one API call:

```text
GET /repos/{owner}/{repo}/dependency-graph/sbom
```

That synchronous SBOM export is closing down on 2026-11-13. The old script also
used `grep -r` over Markdown and treated the result of every predicate as either
`detected` or `not_configured`.

## Privacy behavior

With the default sync setting the old Action did not call ForgeVault. With
`sync: true` it sent a JSON summary containing repository/run metadata and the
old two-state check list. Source files were not intentionally uploaded, but the
README did not provide a precise payload contract. Sync failures made the
Action fail, which could hide the local readiness result. Tokens were passed to
curl without an explicit GitHub Actions mask command.

## Technical defects

1. The deprecated synchronous SBOM endpoint was part of production behavior.
2. SBOM polling, timeout, redirect and rate-limit behavior did not exist.
3. `403`, `404`, API outages and missing permissions were collapsed into
   `not_configured` or a generic failure.
4. The Action assumed `jq` and `curl` but did not document checkout and the
   minimum token permissions clearly.
5. There were no declared Action outputs and no canonical `CheckResult` model.
6. The job summary was a flat table with no grouped evidence, next steps,
   limitations or working Pro CTA.
7. Sync errors invalidated the local result and the payload schema was not
   versioned.
8. There were no Action unit, fixture, privacy-regression or static deprecation
   tests.

## Trust and commercial problems

- The phrase “not configured” could make a permission failure look like a
  customer security gap.
- The Action did not clearly distinguish repository readiness from legal CRA
  applicability or compliance.
- “Install ForgeVault” was not a clickable acquisition path.
- The free/pro boundary was not explained: repository evidence versus
  product-level operations.
- No documented release checklist, API compatibility record, competitor
  positioning note or Marketplace copy file existed for the Action.

This audit is the baseline for `docs/audit/FINAL_IMPROVEMENT_REPORT.md`.
