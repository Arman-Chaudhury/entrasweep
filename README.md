# entrasweep

**Identity-hygiene auditor for Microsoft Entra ID and on-prem Active Directory,
written in PowerShell 7.**

EntraSweep takes a *snapshot* of directory state (a JSON export from Microsoft Graph,
an on-prem AD export, or a fixture) and sweeps it with a pack of read-only hygiene
rules — stale accounts, disabled password expiration, privileged-role sprawl,
admins without MFA, expiring app credentials — then renders the findings as
HTML/JSON/CSV reports with severity summaries.

```
snapshot (JSON) ──► rule pack ──► findings ──► HTML / JSON / CSV + CI exit code
```

**Offline-first by design:** rules never talk to an API, so the whole engine runs and
tests on any OS — including a Linux CI runner with no tenant and no credentials.
Live collectors (Graph, RSAT) are thin adapters that produce snapshots.
EntraSweep is strictly read-only: it recommends remediations, it never performs them.

## Quickstart

```powershell
Import-Module ./src/EntraSweep/EntraSweep.psd1

# Audit the bundled fixture tenant
Invoke-EsAudit -SnapshotPath ./tests/fixtures/tenant-snapshot.json |
    Format-Table RuleId, Severity, Subject, Detail

# Write a JSON report
Invoke-EsAudit -SnapshotPath ./tests/fixtures/tenant-snapshot.json |
    Export-EsReport -Path ./report.json

# Run a single rule, pinned to a reference date
Invoke-EsAudit -SnapshotPath snap.json -Rule stale-account -AsOf ([datetime]'2026-08-16')
```

## Status

Early scaffold — snapshot importer, rules engine, the first two rules
(`stale-account`, `password-expiry-disabled`), and JSON reporting are implemented
and tested. The full rule pack, HTML dashboard, and live Graph/AD collectors are
specced and tracked in [BUILD_PLAN.md](BUILD_PLAN.md). Full design: [SPEC.md](SPEC.md).

## Development

```powershell
Install-Module Pester, PSScriptAnalyzer -Scope CurrentUser
Invoke-Pester -Path ./tests -Output Detailed
Invoke-ScriptAnalyzer -Path ./src -Recurse
```

Requires PowerShell 7.2+ (Windows, macOS, or Linux). CI runs the manifest check,
PSScriptAnalyzer, and the Pester suite on every push.

## Adding a rule

1. Drop `Test-Es<Name>.ps1` in `src/EntraSweep/Rules/` — a pure function
   `snapshot -> findings` (take `-AsOf` if time-based; never call the network).
2. Register it in `Get-EsRuleRegistry` and add it to `FunctionsToExport`.
3. Add positive/negative/edge cases to the fixture tenant and a `Describe` block
   in `tests/`.

## License

MIT
