# Contributing to ForgeVault CRA Readiness

Changes to the Action should preserve the privacy and status guarantees in
`docs/PRIVACY_AND_SYNC.md`.

## Local checks

```bash
bash tests/action/test-run.sh
bash -n action/run.sh
ruby -e "require 'yaml'; YAML.load_file('action/action.yml')"
```

Use the fixture tests for API response behavior. Do not add real credentials,
source archives or customer security data. The Action must keep its default
`sync: false` behavior and must not create issues, pull requests or commits.

## Release changes

Update `CHANGELOG.md`, `RELEASE_CHECKLIST.md` and the compatibility notes when
changing API behavior. Review the official GitHub documentation before changing
an endpoint or permission.
