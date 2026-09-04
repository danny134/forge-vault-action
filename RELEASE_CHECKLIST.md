# ForgeVault CRA Readiness release checklist

## Before tagging

- [ ] Recheck the current official GitHub Action metadata documentation.
- [ ] Recheck the current official SBOM, Code Scanning and permissions docs.
- [ ] Confirm the deprecated synchronous SBOM endpoint is absent from
      production Action files.
- [ ] Run `bash tests/action/test-run.sh`.
- [ ] Run the application verification suite when changing the shared app.
- [ ] Review `SECURITY.md`, dependency updates and CodeQL status.
- [ ] Run a secrets scan and confirm no token appears in the repository.
- [ ] Verify the public Action repository contains exactly one root `action.yml`.

## Job Summary and privacy

- [ ] Run the Action against the good fixture and inspect the generated summary.
- [ ] Run the Action against a minimal/restricted fixture.
- [ ] Confirm status semantics distinguish detected, not detected, unavailable,
      unauthorized, unknown and error.
- [ ] Confirm `sync=false` sends zero ForgeVault requests.
- [ ] Confirm `sync=true` sends only the documented sanitized payload.
- [ ] Confirm a ForgeVault outage leaves the local result successful.
- [ ] Confirm no source code, raw SBOM, dependency list or token is sent/logged.
- [ ] Confirm the ForgeVault Pro CTA is clickable and uses only privacy-safe UTM.

## Release and Marketplace

- [ ] Bump the documented version and update `CHANGELOG.md`.
- [ ] Publish a specific semantic version tag such as `v1.1.0`.
- [ ] Move the compatible major tag `v1` to the reviewed release commit.
- [ ] Preserve existing `v1` compatibility.
- [ ] Use Security as primary and Reporting as secondary category.
- [ ] Inspect the rendered README and Marketplace page on desktop and narrow
      viewport.
- [ ] Confirm release notes mention async SBOM migration, accuracy, privacy,
      Marketplace copy, Pro link and tests.
- [ ] Record remaining limitations in
      `docs/audit/FINAL_IMPROVEMENT_REPORT.md`.
