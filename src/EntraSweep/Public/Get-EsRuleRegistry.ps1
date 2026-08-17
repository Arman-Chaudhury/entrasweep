function Get-EsRuleRegistry {
    <#
    .SYNOPSIS
        Maps rule ids to the functions that implement them.
    .DESCRIPTION
        Adding a rule to EntraSweep means: one file in Rules/, one entry here,
        one fixture-backed test. See SPEC section 4 for the full planned pack.
    #>
    [CmdletBinding()]
    param()

    [ordered]@{
        'stale-account'            = 'Test-EsStaleAccount'
        'password-expiry-disabled' = 'Test-EsPasswordExpiryDisabled'
    }
}
