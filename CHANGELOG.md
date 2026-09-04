# Changelog

All notable changes to ForgeVault CRA Readiness are documented here.

## [1.1.0] - 2026-09-04

### Added

- Canonical `CheckResult` statuses: `DETECTED`, `NOT_DETECTED`,
  `NOT_AVAILABLE`, `NOT_AUTHORIZED`, `UNKNOWN` and `ERROR`.
- Bounded asynchronous GitHub SBOM generation and polling.
- Structured `readiness.json` output and Action outputs for detected, gap and
  unverifiable counts.
- Professional grouped GitHub Job Summary with remediation and a working
  ForgeVault Pro CTA.
- Privacy/sync contract, token permission map, API compatibility record,
  Marketplace copy and fixture-based tests.

### Changed

- Replaced the closing synchronous SBOM API dependency.
- Kept the default informational behavior; `fail-on` is now opt-in.
- Optional ForgeVault sync is sanitized and non-blocking for the local result.
- Marketplace and README copy now expands Cyber Resilience Act and avoids legal
  compliance conclusions.

## [1.0.0]

Initial public Marketplace release.
