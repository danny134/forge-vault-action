# GitHub token permissions for the Action

The workflow should request the smallest permissions needed for the selected
checks. The recommended baseline is:

```yaml
permissions:
  contents: read
  security-events: read
```

No write permission is needed.

| API or signal                                 | Permission                                         | Behavior without it                                                                           |
| --------------------------------------------- | -------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `actions/checkout` and known repository files | `contents: read`                                   | Local checks cannot run after checkout; the Action reports `UNKNOWN` when context is missing. |
| SBOM `generate-report` and `fetch-report`     | `contents: read`                                   | `403` becomes `NOT_AUTHORIZED`, not `NOT_DETECTED`.                                           |
| Security policy Contents API fallback         | `contents: read`                                   | `403` becomes `NOT_AUTHORIZED`.                                                               |
| Code Scanning alerts fallback                 | `security-events: read`                            | `403` becomes `NOT_AUTHORIZED`; local CodeQL workflow detection still works.                  |
| Dependabot configuration                      | none beyond checkout                               | The Action checks the reviewed config file; it does not change alerts.                        |
| ForgeVault sync                               | GitHub Secret containing a ForgeVault action token | Sync is skipped with a warning if the token or product is absent/invalid.                     |

GitHub can reduce permissions and secrets for pull requests from forks. The
Action keeps that fact visible in the result. It never uses write access,
creates issues, opens pull requests or commits changes.

References checked on 2026-09-04:

- [GitHub Action metadata and composite steps](https://docs.github.com/en/actions/reference/workflows-and-actions/metadata-syntax)
- [SBOM REST API](https://docs.github.com/en/rest/dependency-graph/sboms)
- [Code Scanning REST API](https://docs.github.com/en/rest/code-scanning/code-scanning)
- [Dependabot alerts REST API](https://docs.github.com/en/rest/dependabot/alerts)
