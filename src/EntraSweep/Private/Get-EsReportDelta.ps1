function Get-EsReportDelta {
    <#
    .SYNOPSIS
        Compares current active findings against a previous JSON report:
        which findings are new, and how many resolved. Keyed by RuleId|Subject.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Active,

        [Parameter(Mandatory)]
        [string] $PreviousPath
    )

    if (-not (Test-Path -Path $PreviousPath -PathType Leaf)) {
        throw "Previous report not found: $PreviousPath"
    }

    $previous = Get-Content -Path $PreviousPath -Raw | ConvertFrom-Json
    $previousKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($f in @(Get-EsProperty -Object $previous -Name 'findings' -Default @())) {
        [void]$previousKeys.Add("$($f.RuleId)|$($f.Subject)")
    }

    $currentKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $new = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $Active) {
        $key = "$($f.RuleId)|$($f.Subject)"
        [void]$currentKeys.Add($key)
        if (-not $previousKeys.Contains($key)) { $new.Add($f) }
    }

    $resolved = 0
    foreach ($key in $previousKeys) {
        if (-not $currentKeys.Contains($key)) { $resolved++ }
    }

    [pscustomobject]@{
        NewCount      = $new.Count
        ResolvedCount = $resolved
        New           = @($new)
    }
}
