# SBOM handling

ForgeVault supports GitHub-generated SBOM evidence, SPDX and CycloneDX input.
The free Action validates a local root artifact when present and otherwise
uses GitHub's current asynchronous SBOM flow:

1. request generation;
2. poll `fetch-report/{uuid}` for a bounded interval;
3. follow the temporary download URL without the GitHub authorization header;
4. validate the minimal SPDX/CycloneDX shape in a temporary runner file.

The Action never forwards the SBOM contents to ForgeVault. The hosted product
can preserve an SBOM manifest, format, source, hash, package count and storage
path in its private evidence model, but it does not expose that artifact to the
free Action's optional sanitized sync.

GitHub's synchronous `GET /repos/{owner}/{repo}/dependency-graph/sbom` endpoint
is closing down on 2026-11-13. Production Action logic uses only
`generate-report` and `fetch-report`; see
[`GITHUB_API_COMPATIBILITY.md`](GITHUB_API_COMPATIBILITY.md).
