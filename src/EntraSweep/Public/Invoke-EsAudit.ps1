function Invoke-EsAudit {
    <#
    .SYNOPSIS
        Runs the rule pack (or a subset) against a snapshot and emits findings.
    .PARAMETER SnapshotPath
        Path to a snapshot JSON file (see Import-EsSnapshot).
    .PARAMETER Rule
        Optional subset of rule ids to run; defaults to every registered rule.
    .PARAMETER AsOf
        Reference "now" for time-based rules; defaults to the current UTC time.
        Pin this for reproducible runs and tests.
    .PARAMETER ConfigPath
        Optional .psd1 tuning file: per-rule thresholds and Enabled switches,
        keyed by rule id (see Import-EsConfig).
    .PARAMETER BaselinePath
        Optional baseline file of accepted findings (see Import-EsBaseline).
        Matching, unexpired entries mark findings Accepted = true instead of
        removing them.
    .EXAMPLE
        Invoke-EsAudit -SnapshotPath snapshot.json | Export-EsReport -Path report.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SnapshotPath,

        [string[]] $Rule,

        [datetime] $AsOf = [datetime]::UtcNow,

        [string] $ConfigPath,

        [string] $BaselinePath
    )

    $snapshot = Import-EsSnapshot -Path $SnapshotPath
    $registry = Get-EsRuleRegistry
    $config   = if ($ConfigPath) { Import-EsConfig -Path $ConfigPath } else { @{} }
    $baseline = if ($BaselinePath) { @(Import-EsBaseline -Path $BaselinePath) } else { @() }

    if ($Rule) {
        $unknown = @($Rule | Where-Object { -not $registry.Contains($_) })
        if ($unknown.Count -gt 0) {
            throw "Unknown rule id(s): $($unknown -join ', '). Known: $($registry.Keys -join ', ')."
        }
    }

    $findings = foreach ($id in @($registry.Keys)) {
        if ($Rule -and $id -notin $Rule) { continue }

        $ruleConfig = if ($config.Contains($id)) { $config[$id] } else { $null }
        if ($ruleConfig -and $ruleConfig.Contains('Enabled') -and -not $ruleConfig['Enabled']) {
            Write-Verbose "Rule '$id' disabled by config"
            continue
        }

        $command = Get-Command -Name $registry[$id]
        $arguments = @{ Snapshot = $snapshot }
        if ($command.Parameters.ContainsKey('AsOf')) { $arguments['AsOf'] = $AsOf }
        if ($ruleConfig) {
            foreach ($key in $ruleConfig.Keys) {
                if ($key -eq 'Enabled') { continue }
                if ($command.Parameters.ContainsKey($key)) { $arguments[$key] = $ruleConfig[$key] }
                else { Write-Warning "Config key '$key' does not match a parameter of rule '$id'; ignored." }
            }
        }
        Write-Verbose "Running rule '$id' ($($command.Name))"
        & $command @arguments
    }

    foreach ($finding in @($findings)) {
        $accepted = $false
        foreach ($entry in $baseline) {
            if ((Get-EsProperty -Object $entry -Name 'ruleId') -ne $finding.RuleId) { continue }
            if ((Get-EsProperty -Object $entry -Name 'subject') -ne $finding.Subject) { continue }
            $expires = Get-EsProperty -Object $entry -Name 'expires'
            if ($null -ne $expires -and [datetime]$expires -lt $AsOf) { continue }
            $accepted = $true
            break
        }
        $finding | Add-Member -NotePropertyName Accepted -NotePropertyValue $accepted -Force
        $finding
    }
}
