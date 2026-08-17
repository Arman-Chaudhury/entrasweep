function Export-EsReport {
    <#
    .SYNOPSIS
        Writes findings to a JSON report (summary + full findings list).
    .EXAMPLE
        Invoke-EsAudit -SnapshotPath snapshot.json | Export-EsReport -Path report.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [pscustomobject[]] $Finding,

        [Parameter(Mandatory)]
        [string] $Path
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
        $report = [pscustomobject]@{
            generatedAt = [datetime]::UtcNow.ToString('o')
            total       = $all.Count
            bySeverity  = @($all | Group-Object -Property Severity | Sort-Object -Property Name |
                    ForEach-Object { [pscustomobject]@{ severity = $_.Name; count = $_.Count } })
            byRule      = @($all | Group-Object -Property RuleId | Sort-Object -Property Name |
                    ForEach-Object { [pscustomobject]@{ ruleId = $_.Name; count = $_.Count } })
            findings    = @($all)
        }
        $report | ConvertTo-Json -Depth 6 | Set-Content -Path $Path -Encoding utf8
        Write-Verbose "Wrote $($all.Count) finding(s) to $Path"
    }
}
