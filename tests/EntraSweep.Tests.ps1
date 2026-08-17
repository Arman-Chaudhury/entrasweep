BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'src' 'EntraSweep' 'EntraSweep.psd1') -Force
    $fixturePath = Join-Path $PSScriptRoot 'fixtures' 'tenant-snapshot.json'
    # All time-based assertions pin AsOf so the fixture never rots.
    $asOf = [datetime]'2026-08-16'
}

Describe 'Import-EsSnapshot' {
    It 'parses the fixture tenant' {
        $snapshot = Import-EsSnapshot -Path $fixturePath
        $snapshot.Users.Count | Should -Be 7
        $snapshot.Groups.Count | Should -Be 1
        $snapshot.DirectoryRoles.Count | Should -Be 1
        $snapshot.ServicePrincipals.Count | Should -Be 0
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

    It 'skips active, disabled, and recently created accounts' {
        $findings.Subject | Should -Not -Contain 'alice@contoso.example'
        $findings.Subject | Should -Not -Contain 'dave@contoso.example'
        $findings.Subject | Should -Not -Contain 'grace@contoso.example'
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

Describe 'Invoke-EsAudit' {
    It 'runs the full registry and aggregates findings' {
        $findings = @(Invoke-EsAudit -SnapshotPath $fixturePath -AsOf $asOf)
        $findings | Should -HaveCount 3
        ($findings | Where-Object RuleId -EQ 'stale-account') | Should -HaveCount 2
        ($findings | Where-Object RuleId -EQ 'password-expiry-disabled') | Should -HaveCount 1
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
        $report.total | Should -Be 3
        @($report.findings) | Should -HaveCount 3
        ($report.bySeverity | Where-Object severity -EQ 'Medium').count | Should -Be 1
        ($report.byRule | Where-Object ruleId -EQ 'stale-account').count | Should -Be 2
    }

    It 'writes an empty report when there are no findings' {
        $out = Join-Path $TestDrive 'empty.json'
        @() | Export-EsReport -Path $out
        (Get-Content -Path $out -Raw | ConvertFrom-Json).total | Should -Be 0
    }
}

Describe 'Module hygiene' {
    It 'exports exactly the functions declared in the manifest' {
        $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..' 'src' 'EntraSweep' 'EntraSweep.psd1')
        $exported = (Get-Module EntraSweep).ExportedFunctions.Keys | Sort-Object
        @($exported) | Should -Be (@($manifest.FunctionsToExport) | Sort-Object)
    }
}
