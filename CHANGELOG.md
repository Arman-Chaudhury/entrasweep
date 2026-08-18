# Changelog

## v0.1.0 — 2026-08-18

First complete release.

- **Rule pack (8 rules):** `stale-account`, `password-expiry-disabled`,
  `dormant-licensed`, `guest-audit`, `empty-group`, `privileged-sprawl`,
  `admin-no-mfa`, `app-credential-expiry` — all pure functions over a snapshot,
  time-pinned via `-AsOf`.
- **Reports:** self-contained HTML dashboard, JSON with severity/rule summaries,
  flat CSV. `-Previous` adds a new/resolved delta to JSON and HTML.
- **Ops surface:** `.psd1` config for thresholds and rule enable/disable;
  baseline files that mark findings accepted (with optional expiry) instead of
  dropping them; `entrasweep.ps1` wrapper with a `-FailOn` severity gate
  (exit 1) and `-UpdateBaseline`.
- **Collectors:** Microsoft Graph (device-code auth, read-only scopes, paging,
  429 retry, graceful MFA-report fallback) and on-prem Active Directory
  (portable CSV ingestion anywhere, RSAT live route on Windows; users-only in
  this release).
- **Quality:** 46 Pester tests (HTTP layer mocked; no tenant needed),
  PSScriptAnalyzer clean, CI on ubuntu/pwsh.
