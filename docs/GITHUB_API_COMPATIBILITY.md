# GitHub API compatibility

Checked: 2026-09-04 against the current GitHub REST documentation.

| API                                                                   | Purpose                     | Current behavior used by the Action                                                           | Permission              | Source                                                                                           |
| --------------------------------------------------------------------- | --------------------------- | --------------------------------------------------------------------------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------ |
| `GET /repos/{owner}/{repo}/contents/{path}`                           | Security policy fallback    | `200` detected, `404` absent, `403` unauthorized; only the two known policy paths are queried | `contents: read`        | [Repository Contents API](https://docs.github.com/en/rest/repos/contents#get-repository-content) |
| `GET /repos/{owner}/{repo}/dependency-graph/sbom/generate-report`     | Request an SBOM             | `201` returns `sbom_url`; `403` unauthorized; `404` unavailable                               | `contents: read`        | [SBOM API](https://docs.github.com/en/rest/dependency-graph/sboms)                               |
| `GET /repos/{owner}/{repo}/dependency-graph/sbom/fetch-report/{uuid}` | Poll the generated SBOM     | `202` processing; `302` temporary download; `403` unauthorized; `404` unavailable             | `contents: read`        | [SBOM API](https://docs.github.com/en/rest/dependency-graph/sboms)                               |
| Temporary SBOM `Location`                                             | Validate a completed report | Fetched without the GitHub authorization header; minimal SPDX/CycloneDX JSON check only       | URL supplied by GitHub  | [SBOM API](https://docs.github.com/en/rest/dependency-graph/sboms)                               |
| `GET /repos/{owner}/{repo}/code-scanning/alerts`                      | Code Scanning fallback      | `200` detected; `403` unauthorized; `404` unavailable                                         | `security-events: read` | [Code Scanning API](https://docs.github.com/en/rest/code-scanning/code-scanning)                 |

## Deprecated endpoint removed from production logic

The closing synchronous export endpoint is not used by `action/run.sh` or
`action/action.yml`. GitHub's current documentation states that
`GET /repos/{owner}/{repo}/dependency-graph/sbom` becomes inaccessible after
2026-11-13 and directs integrations to the asynchronous flow. A static
regression test prevents that path from returning to the production Action.

The Action uses the API version header documented by GitHub and limits SBOM
polling to a short bounded interval. It does not promise that a missing API
feature means a missing security control.
