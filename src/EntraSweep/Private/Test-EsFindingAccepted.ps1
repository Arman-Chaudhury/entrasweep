function Test-EsFindingAccepted {
    <#
    .SYNOPSIS
        True when a finding carries Accepted = true (baseline-suppressed).
        Findings produced before/without baseline processing lack the
        property entirely and count as active.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Finding
    )
    $prop = $Finding.PSObject.Properties['Accepted']
    return ($null -ne $prop -and $prop.Value -eq $true)
}
