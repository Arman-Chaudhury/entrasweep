function Export-EsReport {
    <#
    .SYNOPSIS
        Writes findings to a JSON report: summary counts, active findings,
        accepted (baselined) findings, and - given a previous report via
        -Previous - a new/resolved delta.
    .EXAMPLE
        Invoke-EsAudit -SnapshotPath snapshot.json | Export-EsReport -Path report.json
    .EXAMPLE
        ... | Export-EsReport -Path today.json -Previous yesterday.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [pscustomobject[]] $Finding,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Previous
    )

    begin {
        $all = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($item in $Finding) {
            if ($null -ne $item) { $all.Add($item) }
        }
    }
    end {
        $active   = @($all | Where-Object { -not (Test-EsFindingAccepted -Finding $_) })
        $accepted = @($all | Where-Object { Test-EsFindingAccepted -Finding $_ })

        $report = [pscustomobject]@{
            generatedAt   = [datetime]::UtcNow.ToString('o')
            total         = $active.Count
            bySeverity    = @($active | Group-Object -Property Severity | Sort-Object -Property Name |
                    ForEach-Object { [pscustomobject]@{ severity = $_.Name; count = $_.Count } })
            byRule        = @($active | Group-Object -Property RuleId | Sort-Object -Property Name |
                    ForEach-Object { [pscustomobject]@{ ruleId = $_.Name; count = $_.Count } })
            acceptedCount = $accepted.Count
            findings      = @($active)
            accepted      = @($accepted)
        }

        if ($Previous) {
            $delta = Get-EsReportDelta -Active $active -PreviousPath $Previous
            $report | Add-Member -NotePropertyName delta -NotePropertyValue ([pscustomobject]@{
                    newCount      = $delta.NewCount
                    resolvedCount = $delta.ResolvedCount
                    new           = @($delta.New)
                })
        }

        $report | ConvertTo-Json -Depth 6 | Set-Content -Path $Path -Encoding utf8
        Write-Verbose "Wrote $($active.Count) active finding(s) to $Path"
    }
}
