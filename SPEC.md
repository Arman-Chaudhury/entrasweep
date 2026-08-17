# EntraSweep — Build Specification

## 1. What it is

EntraSweep is a **PowerShell 7 module** that audits Microsoft identity environments —
**Entra ID** (cloud) and **on-premises Active Directory** — for identity-hygiene and
security-posture issues, then renders the results as a self-contained HTML dashboard,
JSON, and CSV.

It is **offline-first**: every rule runs against a *snapshot* (a JSON/CSV export of
directory state), so the entire rule pack is unit-testable in CI on a Linux runner with
no tenant, no domain, and no credentials. Live collectors (Microsoft Graph for Entra ID,
the ActiveDirectory RSAT module for on-prem AD) are thin adapters that *produce*
snapshots — they are the last thing built, not the first.

```
                       ┌────────────────────────────────────────────┐
  Microsoft Graph ──►  │            snapshot (JSON)                 │
  (Entra ID, live)     │  users / groups / directoryRoles /         │ ──► rules engine ──► findings
                       │  servicePrincipals / capturedAt            │          │
  Get-ADUser exports ─►│                                            │          ▼
  (on-prem, live/CSV)  └────────────────────────────────────────────┘   HTML / JSON / CSV
                                                                        + exit code for CI
```

## 2. Why this design

* **Snapshot boundary** — the audit logic never talks to an API. This makes rules pure
  functions (`snapshot -> findings`), trivially testable with fixtures, and means the
  same rule pack serves both cloud and on-prem once the on-prem export is normalized to
  the snapshot schema.
* **Deterministic time** — every time-based rule takes an `-AsOf` datetime (defaulting
  to now) so tests are reproducible forever.
* **Read-only by design** — collectors request least-privilege *read* Graph scopes only.
  EntraSweep never mutates the directory; remediation is a human's job, guided by each
  finding's `Recommendation`.

## 3. Snapshot schema (v1)

Top-level JSON object:

| Key | Type | Notes |
|---|---|---|
| `schemaVersion` | int | `1` |
| `capturedAt` | ISO-8601 string | when the snapshot was taken |
| `source` | string | `graph` \| `ad-export` \| `fixture` |
| `users` | array | required |
| `groups` | array | optional |
| `directoryRoles` | array | optional; each has `displayName`, `members[]` (user ids) |
| `servicePrincipals` | array | optional; each has `keyCredentials[]`/`passwordCredentials[]` with `endDateTime` |

User object (Graph property names are canonical; the AD adapter maps into these):
`id`, `userPrincipalName`, `displayName`, `accountEnabled`, `userType` (`Member`/`Guest`),
`createdDateTime`, `lastSignInDateTime` (nullable), `passwordPolicies`,
`assignedLicenses[]`, `mfaRegistered` (nullable bool, from authentication-methods report).

Unknown extra properties are ignored (forward-compatible); a missing `users` key is a
hard error.

## 4. Rule pack (stock rules)

Each rule is a function `Test-Es<Name> -Snapshot <obj> [-AsOf <datetime>] [<thresholds>]`
returning zero or more **finding** objects:

```powershell
[pscustomobject]@{ RuleId; Severity ('High'|'Medium'|'Low'); Subject; Detail; Recommendation }
```

| RuleId | Detects | Default threshold | Severity |
|---|---|---|---|
| `stale-account` | enabled account, last sign-in older than N days | 90 days | Medium (High if never signed in) |
| `password-expiry-disabled` | enabled member with `DisablePasswordExpiration` | — | Low |
| `dormant-licensed` | licensed account disabled or stale (wasted spend) | 60 days | Medium |
| `guest-audit` | enabled guests, flagging stale guests | 180 days | Medium |
| `empty-group` | groups with zero members | — | Low |
| `privileged-sprawl` | privileged role membership above a cap (e.g. >5 Global Administrators) | 5 | High |
| `admin-no-mfa` | privileged-role member with `mfaRegistered -ne $true` | — | High |
| `app-credential-expiry` | service-principal secrets/certs expired or expiring within N days | 30 days | High expired / Medium expiring |

Rules are registered in `Get-EsRuleRegistry` (`ruleId -> function name`); `Invoke-EsAudit`
runs all rules or a `-Rule` subset. Adding a rule = add one file in `Rules/` + one
registry line + one fixture-backed test.

## 5. Public API (module `EntraSweep`, prefix `Es`)

| Function | Purpose |
|---|---|
| `Import-EsSnapshot -Path x.json` | parse + validate a snapshot file |
| `Invoke-EsAudit -SnapshotPath x.json [-Rule id,…] [-AsOf dt] [-Config cfg]` | run rules, emit findings |
| `Export-EsReport -Path out.json` (pipeline) | JSON report: summary + findings |
| `Export-EsHtmlReport -Path out.html` (pipeline) | self-contained HTML dashboard |
| `Get-EsRuleRegistry` | list available rules |
| `Connect-EsGraph` / `Export-EsGraphSnapshot` | live Entra ID collector (M6) |
| `Export-EsAdSnapshot` | on-prem AD collector / CSV normalizer (M7) |

CLI usage is plain PowerShell: `Invoke-EsAudit … | Export-EsHtmlReport -Path report.html`.

**Exit-code contract** (for scheduled/CI use, M5): a `-FailOn High|Medium|Low` switch on a
`Invoke-EsAudit … -AsExitCode` wrapper script sets exit 1 when findings at/above that
severity exist, so a nightly scheduled task or pipeline stage can gate on posture.

## 6. Configuration & baselines (M5)

* `entrasweep.config.psd1` — per-rule thresholds and enable/disable, e.g.
  `@{ 'stale-account' = @{ StaleDays = 120 }; 'empty-group' = @{ Enabled = $false } }`.
* **Baseline suppressions** — `baseline.json` of accepted findings (`RuleId` + `Subject`
  + optional expiry date). Suppressed findings are reported in a separate "accepted"
  bucket, not silently dropped. `-UpdateBaseline` regenerates it from current findings.

## 7. Reports (M4/M5)

* **HTML**: single self-contained file (inline CSS, no CDN): severity summary tiles,
  per-rule tables, filterable, plus a delta section ("new since previous report") when
  given `-Previous prior.json`.
* **JSON**: `{ generatedAt, snapshot: {source, capturedAt}, totals, bySeverity[], byRule[], findings[], accepted[] }`.
* **CSV**: flat findings table for Excel/ingest.

## 8. Live collectors

* **Graph (M6)** — uses the `Microsoft.Graph` SDK if present, else raw
  `Invoke-RestMethod` with device-code auth. Read-only scopes:
  `User.Read.All`, `Directory.Read.All`, `AuditLog.Read.All` (sign-in activity),
  `Application.Read.All`, `UserAuthenticationMethod.Read.All`. Must handle paging
  (`@odata.nextLink`) and 429 throttling (honor `Retry-After`). Output = snapshot JSON.
* **On-prem AD (M7)** — on a domain-joined Windows host, wraps
  `Get-ADUser`/`Get-ADGroup` (RSAT); elsewhere, ingests a CSV export produced by a
  bundled one-liner. Maps AD attributes (`lastLogonTimestamp` → `lastSignInDateTime`,
  `PasswordNeverExpires` → `passwordPolicies`, etc.) into the snapshot schema.

## 9. Quality gates

* **Pester 5** tests for every rule (positive + negative + edge: disabled accounts,
  guests, null dates), importer validation, report writers (via `TestDrive:`), config
  and baseline behavior. Fixtures are hand-written synthetic tenants under
  `tests/fixtures/` — no real directory data, ever.
* **PSScriptAnalyzer** clean at `Error` severity (warnings surfaced in CI log).
* **CI** (GitHub Actions, `ubuntu-latest`, `pwsh`): manifest validation
  (`Test-ModuleManifest`), PSScriptAnalyzer, Pester. Runs on every push/PR.
* Cross-platform: module targets PowerShell 7.2+; only M7's live-collection path may
  require Windows (guarded, with the CSV route as the portable fallback).

## 10. Non-goals

* No write operations against any directory.
* No agent/daemon — EntraSweep is run on demand or by a scheduler (cron / Windows
  Task Scheduler); scheduling guidance ships in the README instead of a service.
* No secrets stored: collectors use interactive/device-code or ambient auth only.
