# EntraSweep — Build Plan

Milestones are ordered so the project is demoable (fixture snapshot → findings → report)
from M2 onward. Each milestone lands with its Pester tests and green CI.
See SPEC.md for the full design.

- [x] **M1 — Snapshot model & importer.** JSON snapshot schema v1, `Import-EsSnapshot`
      with validation (missing `users` = hard error), synthetic tenant fixture.
      *(scaffolded)*
- [x] **M2 — Rules engine core.** Finding object model (`New-EsFinding`), rule registry
      (`Get-EsRuleRegistry`), `Invoke-EsAudit` with `-Rule` filtering and deterministic
      `-AsOf`; first two rules: `stale-account`, `password-expiry-disabled`; JSON export
      (`Export-EsReport`). *(scaffolded)*
- [ ] **M3 — Full stock rule pack.** `dormant-licensed`, `guest-audit`, `empty-group`,
      `privileged-sprawl`, `admin-no-mfa`, `app-credential-expiry` — each with
      fixture-backed positive/negative/edge tests (SPEC §4).
- [ ] **M4 — HTML report.** `Export-EsHtmlReport`: self-contained single-file dashboard
      (severity tiles, per-rule tables, client-side filter), no external assets.
- [ ] **M5 — Ops surface.** CSV export, `entrasweep.config.psd1` thresholds,
      baseline suppression file with expiries + `-UpdateBaseline`, `-Previous` delta
      section in reports, `-FailOn` exit-code contract for scheduled/CI runs.
- [ ] **M6 — Entra ID live collector.** `Connect-EsGraph` + `Export-EsGraphSnapshot`
      via Microsoft Graph (device-code auth, least-privilege read scopes, paging,
      429/Retry-After handling). Tests mock the HTTP layer.
- [ ] **M7 — On-prem AD collector.** `Export-EsAdSnapshot`: RSAT wrapper on
      domain-joined Windows; portable CSV-export ingestion path everywhere else;
      attribute mapping into snapshot schema v1.
- [ ] **M8 — Packaging & docs.** PSGallery-ready manifest polish, versioned CHANGELOG,
      README walkthrough with screenshots of the HTML report, scheduling guidance
      (cron + Task Scheduler), tag v0.1.0.
