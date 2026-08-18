function Import-EsBaseline {
    <#
    .SYNOPSIS
        Loads a baseline (accepted-findings) file. Each entry names a ruleId
        and subject, with an optional 'expires' date after which the
        acceptance lapses. Matching findings are reported as accepted rather
        than active - suppressed, but never silently dropped.
    .EXAMPLE
        Import-EsBaseline -Path baseline.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Baseline file not found: $Path"
    }

    $raw = Get-Content -Path $Path -Raw | ConvertFrom-Json
    $entries = Get-EsProperty -Object $raw -Name 'entries'
    if ($null -eq $entries) {
        throw "Baseline '$Path' is missing the 'entries' array."
    }
    @($entries)
}
