# entrasweep

**A checkup tool for the user accounts a company keeps in Microsoft's systems.**

Every company that runs on Microsoft has a directory of user accounts (Entra ID
in the cloud, Active Directory on their own servers). Over time it fills with
junk: people who left but still have accounts, admins without two-factor login,
licenses nobody uses, groups with no members. Each one is a security hole or a
wasted dollar, and finding them by hand means clicking through hundreds of
screens.

entrasweep takes a snapshot of that directory and checks it against eight rules
for that kind of problem, then gives you a report you can open in a browser
(plus spreadsheet and JSON versions). Run it again next month and it shows you
what changed. It only ever reads: it suggests fixes but never makes them. I
wrote it in PowerShell because that is what Windows admins actually use.

```
snapshot (JSON) ──► rule pack ──► findings ──► HTML / JSON / CSV + exit code
```

The rules never talk to Microsoft directly. They work on a saved snapshot, so
the whole thing runs and tests on any computer, even one with no Microsoft
account at all. The pieces that pull live data are small adapters whose only job
is to produce a snapshot.

## The rules

| Rule id | Flags | Severity |
|---|---|---|
| `stale-account` | enabled members not signed in for 90+ days (never = worse) | Medium / High |
| `password-expiry-disabled` | enabled members with password expiration off | Low |
| `dormant-licensed` | licenses held by disabled or 60+-day-idle accounts | Medium |
| `guest-audit` | guests idle 180+ days or invited-and-never-arrived | Medium |
| `empty-group` | groups with explicitly zero members | Low |
| `privileged-sprawl` | privileged roles above a membership cap (default 5) | High |
| `admin-no-mfa` | privileged-role members with MFA registration = false | High |
| `app-credential-expiry` | SP secrets/certs expired or expiring within 30 days | High / Medium |

Every threshold is tunable per rule via a config file; every time-based rule takes
`-AsOf` for reproducible runs.

## Quickstart

```powershell
Import-Module ./src/EntraSweep/EntraSweep.psd1

# Audit the bundled fixture tenant and open the dashboard
Invoke-EsAudit -SnapshotPath ./tests/fixtures/tenant-snapshot.json |
    Export-EsHtmlReport -Path ./report.html

# Or as a table in the terminal
Invoke-EsAudit -SnapshotPath ./tests/fixtures/tenant-snapshot.json |
    Format-Table RuleId, Severity, Subject, Detail
```

## Collecting real snapshots

**Entra ID (any OS):** device-code sign-in with read-only scopes; the token stays
in memory, nothing is written to disk.

```powershell
Connect-EsGraph                     # follow the device-code prompt
Export-EsGraphSnapshot -OutFile tenant.json
```

The MFA-registration report requires an Entra premium license; without it the
snapshot omits `mfaRegistered` and `admin-no-mfa` politely skips.

**On-prem AD:** run live on a domain-joined Windows host
(`Export-EsAdSnapshot -Live -OutFile ad.json`), or export a CSV on any domain
machine and ingest it anywhere — the exact `Get-ADUser | Export-Csv` one-liner is
in `Get-Help Export-EsAdSnapshot -Detailed`. The AD snapshot covers users in this
release; groups/roles remain Graph territory.

## Scheduled sweeps and CI gates

`entrasweep.ps1` is the unattended entry point: it audits, writes whichever
reports you ask for, and exits 1 when active findings reach `-FailOn` severity.

```powershell
./entrasweep.ps1 -SnapshotPath tenant.json `
    -OutHtml report.html -OutJson report.json -Previous yesterday.json `
    -ConfigPath entrasweep.config.psd1 -BaselinePath baseline.json `
    -FailOn High
```

* **cron (Linux/macOS):**
  `0 7 * * * pwsh -NoProfile -File /opt/entrasweep/entrasweep.ps1 -SnapshotPath ... -FailOn High || notify-send "entrasweep gate failed"`
* **Windows Task Scheduler:**
  `schtasks /Create /SC DAILY /ST 07:00 /TN entrasweep /TR "pwsh -NoProfile -File C:\entrasweep\entrasweep.ps1 -SnapshotPath ... -FailOn High"`

**Tuning:** `examples/entrasweep.config.psd1` shows per-rule thresholds and
disabling. **Baselines:** accepted findings (optionally with an expiry date) move
to an "accepted" bucket — visible in every report, excluded from totals and the
gate. Regenerate with `-UpdateBaseline`. **Deltas:** pass yesterday's JSON report
as `-Previous` and reports gain "N new, M resolved".

## Development

```powershell
Install-Module Pester, PSScriptAnalyzer -Scope CurrentUser
Invoke-Pester -Path ./tests -Output Detailed     # 46 tests, no tenant needed
Invoke-ScriptAnalyzer -Path ./src -Recurse
```

Requires PowerShell 7.2+ (Windows, macOS, Linux). CI validates the manifest,
lints module + wrapper, and runs the Pester suite on every push. Design docs:
[SPEC.md](SPEC.md) · [BUILD_PLAN.md](BUILD_PLAN.md) · [CHANGELOG.md](CHANGELOG.md).

### Adding a rule

1. Drop `Test-Es<Name>.ps1` in `src/EntraSweep/Rules/` — a pure function
   `snapshot -> findings` (take `-AsOf` if time-based; never call the network).
2. Register it in `Get-EsRuleRegistry` and add it to `FunctionsToExport`.
3. Add positive/negative/edge cases to the fixture tenant and a `Describe` block
   in `tests/`.

## License

MIT
