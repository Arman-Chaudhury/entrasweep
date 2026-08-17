function Get-EsProperty {
    <#
    .SYNOPSIS
        Safe property access for snapshot objects: optional keys may be absent
        from JSON exports, so absence and null both resolve to a default.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)] [string] $Name,
        $Default = $null
    )
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

function New-EsFinding {
    <#
    .SYNOPSIS
        Constructs the finding object every rule emits (SPEC section 4).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object; changes no system state.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RuleId,
        [Parameter(Mandatory)] [ValidateSet('High', 'Medium', 'Low')] [string] $Severity,
        [Parameter(Mandatory)] [string] $Subject,
        [Parameter(Mandatory)] [string] $Detail,
        [string] $Recommendation = ''
    )
    [pscustomobject]@{
        RuleId         = $RuleId
        Severity       = $Severity
        Subject        = $Subject
        Detail         = $Detail
        Recommendation = $Recommendation
    }
}
