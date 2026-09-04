# Competitor positioning audit

Checked: 2026-09-04. This is a high-level positioning review of visible GitHub
Marketplace Actions; it does not copy their text or assets.

| Market pattern       | Examples observed                                                                                                                                                                                | What users are being offered                                    | ForgeVault distinction                                                                                                    |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| SBOM generation      | [Anchore SBOM Action](https://github.com/marketplace/actions/anchore-sbom-action), [sbomify](https://github.com/marketplace/actions/sbomify)                                                     | Generate, enrich, attest or upload an SBOM                      | ForgeVault does not compete as an SBOM generator; the free Action checks readiness evidence and stays private by default. |
| SBOM transmission    | [Manifest Cyber SBOM Transmitter](https://github.com/marketplace/actions/manifest-cyber-sbom-transmitter), [SBOM Observer](https://github.com/marketplace/actions/sbom-observer-scan-and-upload) | Move SBOM data into a vendor platform for inventory or analysis | ForgeVault optional sync sends only a sanitized readiness summary, never raw SBOM contents.                               |
| CI security controls | Code scanning, dependency review and hardened-runner Actions in GitHub Marketplace                                                                                                               | Enforce a focused build or runtime security control             | ForgeVault connects several repository signals to product-level CRA operations and human review.                          |

## Positioning decision

The free Action should be discovered for **Cyber Resilience Act readiness for
GitHub**, not for generic automated compliance or package updates. Its useful
boundary is:

```text
repository evidence
    → product mapping
    → release and security signal context
    → human assessment
    → CRA case and evidence workflow in ForgeVault Pro
```

This avoids claiming to be the “best CRA scanner” and gives the Marketplace
visitor a clear reason to try the Action before considering the paid product.

## Discoverability test plan

Search the GitHub Marketplace manually for `CRA`, `Cyber Resilience Act`, `SBOM`
and `CRA readiness` after each Marketplace metadata update. Record only the
approximate position and whether the listing is understandable; do not rank-
manipulate, spam or create artificial installs.
