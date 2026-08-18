function Export-EsCsvReport {
    <#
    .SYNOPSIS
        Writes findings to a flat CSV for Excel or downstream ingestion.
    .EXAMPLE
        Invoke-EsAudit -SnapshotPath snap.json | Export-EsCsvReport -Path findings.csv
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
        $rows = @($all | ForEach-Object {
                [pscustomobject]@{
                    RuleId         = $_.RuleId
                    Severity       = $_.Severity
                    Subject        = $_.Subject
                    Detail         = $_.Detail
                    Recommendation = $_.Recommendation
                    Accepted       = (Test-EsFindingAccepted -Finding $_)
                }
            })
        if ($rows.Count -eq 0) {
            Set-Content -Path $Path -Encoding utf8 `
                -Value '"RuleId","Severity","Subject","Detail","Recommendation","Accepted"'
        }
        else {
            $rows | Export-Csv -Path $Path -Encoding utf8 -NoTypeInformation
        }
        Write-Verbose "Wrote $($rows.Count) row(s) to $Path"
    }
}
