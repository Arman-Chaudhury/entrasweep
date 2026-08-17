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
    .EXAMPLE
        Invoke-EsAudit -SnapshotPath snapshot.json | Export-EsReport -Path report.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SnapshotPath,

        [string[]] $Rule,

        [datetime] $AsOf = [datetime]::UtcNow
    )

    $snapshot = Import-EsSnapshot -Path $SnapshotPath
    $registry = Get-EsRuleRegistry

    if ($Rule) {
        $unknown = @($Rule | Where-Object { -not $registry.Contains($_) })
        if ($unknown.Count -gt 0) {
            throw "Unknown rule id(s): $($unknown -join ', '). Known: $($registry.Keys -join ', ')."
        }
    }

    foreach ($id in @($registry.Keys)) {
        if ($Rule -and $id -notin $Rule) { continue }
        $command = Get-Command -Name $registry[$id]
        $arguments = @{ Snapshot = $snapshot }
        if ($command.Parameters.ContainsKey('AsOf')) { $arguments['AsOf'] = $AsOf }
        Write-Verbose "Running rule '$id' ($($command.Name))"
        & $command @arguments
    }
}
