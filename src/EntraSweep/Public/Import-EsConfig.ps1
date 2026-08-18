function Import-EsConfig {
    <#
    .SYNOPSIS
        Loads a rule-tuning config (.psd1): per-rule thresholds and
        enable/disable switches, keyed by rule id.
    .EXAMPLE
        Import-EsConfig -Path examples/entrasweep.config.psd1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Config file not found: $Path"
    }

    $data = Import-PowerShellDataFile -Path $Path
    $known = Get-EsRuleRegistry
    foreach ($key in $data.Keys) {
        if (-not $known.Contains($key)) {
            Write-Warning "Config references unknown rule id '$key'; it will have no effect."
        }
    }
    $data
}
