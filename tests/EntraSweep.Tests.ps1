BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'src' 'EntraSweep' 'EntraSweep.psd1') -Force
    $fixturePath = Join-Path $PSScriptRoot 'fixtures' 'tenant-snapshot.json'
    # All time-based assertions pin AsOf so the fixture never rots.
    $asOf = [datetime]'2026-08-16'
}

Describe 'Import-EsSnapshot' {
    It 'parses the fixture tenant' {
        $snapshot = Import-EsSnapshot -Path $fixturePath
        $snapshot.Users.Count | Should -Be 11
        $snapshot.Groups.Count | Should -Be 3
        $snapshot.DirectoryRoles.Count | Should -Be 2
        $snapshot.ServicePrincipals.Count | Should -Be 4
        $snapshot.Source | Should -Be 'fixture'
        $snapshot.CapturedAt | Should -BeOfType [datetime]
    }

    It 'throws on a missing file' {
        { Import-EsSnapshot -Path (Join-Path $TestDrive 'nope.json') } | Should -Throw '*not found*'
    }

    It 'throws when the users collection is absent' {
        $bad = Join-Path $TestDrive 'bad.json'
        '{"schemaVersion": 1, "groups": []}' | Set-Content -Path $bad
        { Import-EsSnapshot -Path $bad } | Should -Throw "*required 'users'*"
    }
}

Describe 'Rule: stale-account' {
    BeforeAll {
        $snapshot = Import-EsSnapshot -Path $fixturePath
        $findings = @(Test-EsStaleAccount -Snapshot $snapshot -AsOf $asOf)
    }

    It 'flags the account stale beyond 90 days as Medium' {
        $bob = $findings | Where-Object Subject -EQ 'bob@contoso.example'
        $bob | Should -HaveCount 1
        $bob.Severity | Should -Be 'Medium'
    }

    It 'flags the old never-signed-in account as High' {
        $carol = $findings | Where-Object Subject -EQ 'carol@contoso.example'
        $carol | Should -HaveCount 1
        $carol.Severity | Should -Be 'High'
    }

    It 'skips active, disabled, recently created, and guest accounts' {
        $findings.Subject | Should -Not -Contain 'alice@contoso.example'
        $findings.Subject | Should -Not -Contain 'dave@contoso.example'
        $findings.Subject | Should -Not -Contain 'grace@contoso.example'
        $findings.Subject | Should -Not -Contain 'iris_partner.example#EXT#@contoso.example'
        $findings | Should -HaveCount 2
    }

    It 'respects a custom threshold' {
        # At 300 days, bob (last sign-in ~6.5 months back) is no longer stale.
        $loose = @(Test-EsStaleAccount -Snapshot $snapshot -AsOf $asOf -StaleDays 300)
        $loose.Subject | Should -Not -Contain 'bob@contoso.example'
    }
}

Describe 'Rule: password-expiry-disabled' {
    BeforeAll {
        $snapshot = Import-EsSnapshot -Path $fixturePath
        $findings = @(Test-EsPasswordExpiryDisabled -Snapshot $snapshot)
    }

    It 'flags only the enabled member with expiration disabled (guests excluded)' {
        $findings | Should -HaveCount 1
        $findings[0].Subject | Should -Be 'erin@contoso.example'
        $findings[0].Severity | Should -Be 'Low'
    }
}

Describe 'Rule: dormant-licensed' {
    BeforeAll {
        $snapshot = Import-EsSnapshot -Path $fixturePath
        $findings = @(Test-EsDormantLicensedAccount -Snapshot $snapshot -AsOf $asOf)
    }

    It 'flags the disabled-but-licensed account and the dormant licensed account' {
        $findings | Should -HaveCount 2
        $findings.Subject | Should -Contain 'dave@contoso.example'
        $findings.Subject | Should -Contain 'henry@contoso.example'
    }

    It 'leaves active licensed accounts alone' {
        $findings.Subject | Should -Not -Contain 'alice@contoso.example'
        $findings.Subject | Should -Not -Contain 'erin@contoso.example'
    }
}

Describe 'Rule: guest-audit' {
    BeforeAll {
        $snapshot = Import-EsSnapshot -Path $fixturePath
        $findings = @(Test-EsGuestAccount -Snapshot $snapshot -AsOf $asOf)
    }

    It 'flags only the stale guest' {
        $findings | Should -HaveCount 1
        $findings[0].Subject | Should -Be 'iris_partner.example#EXT#@contoso.example'
        $findings[0].Severity | Should -Be 'Medium'
    }
}

Describe 'Rule: empty-group' {
    It 'flags explicitly empty groups and skips groups without membership data' {
        $snapshot = Import-EsSnapshot -Path $fixturePath
        $findings = @(Test-EsEmptyGroup -Snapshot $snapshot)
        $findings | Should -HaveCount 1
        $findings[0].Subject | Should -Be 'Legacy VPN Users'
    }
}

Describe 'Rule: privileged-sprawl' {
    BeforeAll {
        $snapshot = Import-EsSnapshot -Path $fixturePath
    }

    It 'stays quiet under the default cap' {
        @(Test-EsPrivilegedRoleSprawl -Snapshot $snapshot) | Should -HaveCount 0
    }

    It 'flags a privileged role above a tightened cap' {
        $findings = @(Test-EsPrivilegedRoleSprawl -Snapshot $snapshot -MaxMembers 2)
        $findings | Should -HaveCount 1
        $findings[0].Subject | Should -Be 'Global Administrator'
        $findings[0].Severity | Should -Be 'High'
    }

    It 'ignores non-privileged roles even when they exceed the cap' {
        # Helpdesk Administrator has 2 members, above this cap, but is not in
        # the privileged set - only Global Administrator may be flagged.
        $findings = @(Test-EsPrivilegedRoleSprawl -Snapshot $snapshot -MaxMembers 1)
        $findings.Subject | Should -Not -Contain 'Helpdesk Administrator'
        $findings.Subject | Should -Contain 'Global Administrator'
    }
}

Describe 'Rule: admin-no-mfa' {
    It 'flags the privileged member with MFA false, skipping unknown and registered' {
        $snapshot = Import-EsSnapshot -Path $fixturePath
        $findings = @(Test-EsAdminMfaRegistration -Snapshot $snapshot)
        $findings | Should -HaveCount 1
        $findings[0].Subject | Should -Be 'judy@contoso.example'
        $findings[0].Severity | Should -Be 'High'
    }
}

Describe 'Rule: app-credential-expiry' {
    BeforeAll {
        $snapshot = Import-EsSnapshot -Path $fixturePath
        $findings = @(Test-EsAppCredentialExpiry -Snapshot $snapshot -AsOf $asOf)
    }

    It 'flags expired credentials High and soon-to-expire Medium' {
        $findings | Should -HaveCount 2
        ($findings | Where-Object Subject -EQ 'HR Sync App').Severity | Should -Be 'High'
        ($findings | Where-Object Subject -EQ 'Billing Exporter').Severity | Should -Be 'Medium'
    }

    It 'ignores healthy and credential-less service principals' {
        $findings.Subject | Should -Not -Contain 'Wiki Bot'
        $findings.Subject | Should -Not -Contain 'Legacy Connector (no creds)'
    }
}

Describe 'Invoke-EsAudit' {
    It 'runs the full registry and aggregates findings' {
        $findings = @(Invoke-EsAudit -SnapshotPath $fixturePath -AsOf $asOf)
        $findings | Should -HaveCount 10
        ($findings | Where-Object RuleId -EQ 'stale-account') | Should -HaveCount 2
        ($findings | Where-Object RuleId -EQ 'password-expiry-disabled') | Should -HaveCount 1
        ($findings | Where-Object RuleId -EQ 'dormant-licensed') | Should -HaveCount 2
        ($findings | Where-Object RuleId -EQ 'guest-audit') | Should -HaveCount 1
        ($findings | Where-Object RuleId -EQ 'empty-group') | Should -HaveCount 1
        ($findings | Where-Object RuleId -EQ 'privileged-sprawl') | Should -HaveCount 0
        ($findings | Where-Object RuleId -EQ 'admin-no-mfa') | Should -HaveCount 1
        ($findings | Where-Object RuleId -EQ 'app-credential-expiry') | Should -HaveCount 2
    }

    It 'honors a rule subset' {
        $findings = @(Invoke-EsAudit -SnapshotPath $fixturePath -AsOf $asOf -Rule 'password-expiry-disabled')
        $findings | Should -HaveCount 1
        $findings[0].RuleId | Should -Be 'password-expiry-disabled'
    }

    It 'rejects unknown rule ids' {
        { Invoke-EsAudit -SnapshotPath $fixturePath -Rule 'no-such-rule' } |
            Should -Throw '*Unknown rule id*'
    }
}

Describe 'Export-EsReport' {
    It 'writes a JSON report with summary counts' {
        $out = Join-Path $TestDrive 'report.json'
        Invoke-EsAudit -SnapshotPath $fixturePath -AsOf $asOf | Export-EsReport -Path $out

        $report = Get-Content -Path $out -Raw | ConvertFrom-Json
        $report.total | Should -Be 10
        @($report.findings) | Should -HaveCount 10
        ($report.bySeverity | Where-Object severity -EQ 'High').count | Should -Be 3
        ($report.bySeverity | Where-Object severity -EQ 'Medium').count | Should -Be 5
        ($report.bySeverity | Where-Object severity -EQ 'Low').count | Should -Be 2
        ($report.byRule | Where-Object ruleId -EQ 'stale-account').count | Should -Be 2
    }

    It 'writes an empty report when there are no findings' {
        $out = Join-Path $TestDrive 'empty.json'
        @() | Export-EsReport -Path $out
        (Get-Content -Path $out -Raw | ConvertFrom-Json).total | Should -Be 0
    }
}

Describe 'Config tuning' {
    It 'applies thresholds and disables rules from a config file' {
        $cfg = Join-Path $TestDrive 'tune.psd1'
        @'
@{
    'stale-account' = @{ StaleDays = 400 }
    'empty-group'   = @{ Enabled = $false }
}
'@ | Set-Content -Path $cfg
        $findings = @(Invoke-EsAudit -SnapshotPath $fixturePath -AsOf $asOf -ConfigPath $cfg)
        # At 400 days bob is no longer stale (carol still is: never signed in);
        # empty-group is disabled outright.
        $findings | Should -HaveCount 8
        ($findings | Where-Object RuleId -EQ 'stale-account') | Should -HaveCount 1
        ($findings | Where-Object RuleId -EQ 'empty-group') | Should -HaveCount 0
    }

    It 'warns on config keys that match no rule parameter and continues' {
        $cfg = Join-Path $TestDrive 'bogus.psd1'
        "@{ 'guest-audit' = @{ Bogus = 5 } }" | Set-Content -Path $cfg
        $findings = @(Invoke-EsAudit -SnapshotPath $fixturePath -AsOf $asOf -ConfigPath $cfg -WarningAction SilentlyContinue)
        $findings | Should -HaveCount 10
    }
}

Describe 'Baseline suppression' {
    BeforeAll {
        $baselinePath = Join-Path $TestDrive 'baseline.json'
        @'
{
  "entries": [
    { "ruleId": "stale-account", "subject": "bob@contoso.example" },
    { "ruleId": "admin-no-mfa", "subject": "judy@contoso.example", "expires": "2026-01-01" }
  ]
}
'@ | Set-Content -Path $baselinePath
        $findings = @(Invoke-EsAudit -SnapshotPath $fixturePath -AsOf $asOf -BaselinePath $baselinePath)
    }

    It 'marks matching unexpired entries accepted without dropping them' {
        $findings | Should -HaveCount 10
        $accepted = @($findings | Where-Object Accepted)
        $accepted | Should -HaveCount 1
        $accepted[0].Subject | Should -Be 'bob@contoso.example'
    }

    It 'ignores baseline entries that have expired' {
        ($findings | Where-Object Subject -EQ 'judy@contoso.example').Accepted | Should -BeFalse
    }

    It 'excludes accepted findings from report totals but lists them' {
        $out = Join-Path $TestDrive 'baselined.json'
        $findings | Export-EsReport -Path $out
        $report = Get-Content -Path $out -Raw | ConvertFrom-Json
        $report.total | Should -Be 9
        $report.acceptedCount | Should -Be 1
        @($report.accepted)[0].Subject | Should -Be 'bob@contoso.example'
    }
}

Describe 'Export-EsCsvReport' {
    It 'writes a flat CSV with an Accepted column' {
        $out = Join-Path $TestDrive 'findings.csv'
        Invoke-EsAudit -SnapshotPath $fixturePath -AsOf $asOf | Export-EsCsvReport -Path $out
        $rows = @(Import-Csv -Path $out)
        $rows | Should -HaveCount 10
        $rows[0].PSObject.Properties.Name | Should -Contain 'Accepted'
    }

    It 'writes a header-only file when there are no findings' {
        $out = Join-Path $TestDrive 'empty.csv'
        @() | Export-EsCsvReport -Path $out
        @(Import-Csv -Path $out) | Should -HaveCount 0
        (Get-Content -Path $out -Raw) | Should -Match 'RuleId'
    }
}

Describe 'Report delta (-Previous)' {
    It 'computes new and resolved counts against a previous report' {
        $subsetPath = Join-Path $TestDrive 'subset.json'
        Invoke-EsAudit -SnapshotPath $fixturePath -AsOf $asOf -Rule 'password-expiry-disabled' |
            Export-EsReport -Path $subsetPath

        $fullPath = Join-Path $TestDrive 'full.json'
        Invoke-EsAudit -SnapshotPath $fixturePath -AsOf $asOf |
            Export-EsReport -Path $fullPath -Previous $subsetPath

        $report = Get-Content -Path $fullPath -Raw | ConvertFrom-Json
        $report.delta.newCount | Should -Be 9
        $report.delta.resolvedCount | Should -Be 0

        # And the other direction: the subset against the full report.
        $subset2 = Join-Path $TestDrive 'subset2.json'
        Invoke-EsAudit -SnapshotPath $fixturePath -AsOf $asOf -Rule 'password-expiry-disabled' |
            Export-EsReport -Path $subset2 -Previous $fullPath
        $report2 = Get-Content -Path $subset2 -Raw | ConvertFrom-Json
        $report2.delta.newCount | Should -Be 0
        $report2.delta.resolvedCount | Should -Be 9
    }
}

Describe 'entrasweep.ps1 wrapper' {
    BeforeAll {
        $wrapperPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'entrasweep.ps1')).Path
        $pwshPath = (Get-Process -Id $PID).Path
    }

    It 'exits 1 when the FailOn gate trips' {
        & $pwshPath -NoProfile -File $wrapperPath -SnapshotPath $fixturePath -AsOf '2026-08-16' -FailOn High | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'exits 0 when no active finding reaches the gate' {
        & $pwshPath -NoProfile -File $wrapperPath -SnapshotPath $fixturePath -AsOf '2026-08-16' -Rule empty-group -FailOn High | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'writes a baseline that silences the next gated run' {
        $bl = Join-Path $TestDrive 'wrapper-baseline.json'
        $html = Join-Path $TestDrive 'wrapper-report.html'

        & $pwshPath -NoProfile -File $wrapperPath -SnapshotPath $fixturePath -AsOf '2026-08-16' -BaselinePath $bl -UpdateBaseline | Out-Null
        $LASTEXITCODE | Should -Be 0
        Test-Path $bl | Should -BeTrue

        & $pwshPath -NoProfile -File $wrapperPath -SnapshotPath $fixturePath -AsOf '2026-08-16' -BaselinePath $bl -FailOn Low -OutHtml $html | Out-Null
        $LASTEXITCODE | Should -Be 0
        Test-Path $html | Should -BeTrue
    }
}

Describe 'Export-EsHtmlReport' {
    It 'writes a self-contained dashboard with tiles and rule sections' {
        $out = Join-Path $TestDrive 'report.html'
        Invoke-EsAudit -SnapshotPath $fixturePath -AsOf $asOf | Export-EsHtmlReport -Path $out -Title 'Contoso sweep'

        $html = Get-Content -Path $out -Raw
        $html | Should -Match 'Contoso sweep'
        $html | Should -Match 'Total active'
        $html | Should -Match 'stale-account'
        $html | Should -Match 'HR Sync App'
        $html | Should -Match '10 active finding'
        $html | Should -Not -Match 'http[s]?://'   # no external assets
    }

    It 'HTML-encodes attacker-controlled fields' {
        $out = Join-Path $TestDrive 'xss.html'
        $finding = [pscustomobject]@{
            RuleId = 'test-rule'; Severity = 'High'
            Subject = '<script>alert(1)</script>'; Detail = 'd'; Recommendation = ''
        }
        @($finding) | Export-EsHtmlReport -Path $out
        $html = Get-Content -Path $out -Raw
        $html | Should -Not -Match '<script>alert'
        $html | Should -Match '&lt;script&gt;'
    }

    It 'separates accepted findings from active ones' {
        $out = Join-Path $TestDrive 'accepted.html'
        $finding = [pscustomobject]@{
            RuleId = 'test-rule'; Severity = 'Low'
            Subject = 's'; Detail = 'd'; Recommendation = ''; Accepted = $true
        }
        @($finding) | Export-EsHtmlReport -Path $out
        $html = Get-Content -Path $out -Raw
        $html | Should -Match 'Clean sweep'
        $html | Should -Match '1 accepted \(baselined\)'
    }
}

Describe 'Module hygiene' {
    It 'exports exactly the functions declared in the manifest' {
        $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..' 'src' 'EntraSweep' 'EntraSweep.psd1')
        $exported = (Get-Module EntraSweep).ExportedFunctions.Keys | Sort-Object
        @($exported) | Should -Be (@($manifest.FunctionsToExport) | Sort-Object)
    }
}
