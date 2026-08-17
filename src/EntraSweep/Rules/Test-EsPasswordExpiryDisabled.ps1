function Test-EsPasswordExpiryDisabled {
    <#
    .SYNOPSIS
        Rule 'password-expiry-disabled': enabled member accounts carrying the
        DisablePasswordExpiration policy. Guests are excluded (their password
        posture belongs to their home tenant).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Snapshot
    )

    foreach ($user in $Snapshot.Users) {
        if (-not (Get-EsProperty -Object $user -Name 'accountEnabled' -Default $false)) { continue }
        if ((Get-EsProperty -Object $user -Name 'userType' -Default 'Member') -eq 'Guest') { continue }

        $policies = Get-EsProperty -Object $user -Name 'passwordPolicies' -Default ''
        if ($policies -match 'DisablePasswordExpiration') {
            $upn = Get-EsProperty -Object $user -Name 'userPrincipalName' -Default '(unknown upn)'
            New-EsFinding -RuleId 'password-expiry-disabled' -Severity Low -Subject $upn `
                -Detail 'Password expiration is disabled for this enabled member account.' `
                -Recommendation 'Confirm the account is protected by MFA/conditional access, or re-enable password expiration.'
        }
    }
}
