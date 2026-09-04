# ForgeVault CRA Readiness

Free GitHub Action that checks the repository signals a product-security team
needs for CRA readiness: `SECURITY.md`, SBOM, dependency graph, Dependabot,
code scanning, security contact, product mapping and incident owner.

**Does not exfiltrate by default.** Local execution only. Optional `sync: true` with token sends sanitized summary.

## Usage

```yaml
- uses: danny134/forge-vault-action@v1
```

An example workflow is in [`examples/readiness.yml`](examples/readiness.yml).

The workflow needs read-only repository metadata for the dependency-graph check:

```yaml
permissions:
  contents: read
```

With sync:

```yaml
- uses: danny134/forge-vault-action@v1
  with:
    sync: true
    token: ${{ secrets.FORGEVAULT_TOKEN }}
    product: northstar-desktop-agent
```

Create the token in ForgeVault → Settings → GitHub Action. It is shown once,
stored only as a hash, and can be revoked by a workspace administrator. The
sync endpoint accepts only the sanitized check summary; source code and raw
dependency data are never uploaded.

`readiness.json` is written in the runner workspace for inspection and contains
only check results plus GitHub run metadata. The Action never creates issues or
pull requests.

Branding: marketplace-ready, no automatic issues or pull requests.
