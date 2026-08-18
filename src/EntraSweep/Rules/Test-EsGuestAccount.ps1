function Test-EsGuestAccount {
    <#
    .SYNOPSIS
        Rule 'guest-audit': enabled guest accounts that have gone stale (or were
        invited and never signed in). Guests accumulate silently; this rule is
        the periodic sweep for them.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Snapshot,
        [datetime] $AsOf = [datetime]::UtcNow,
        [ValidateRange(1, 3650)] [int] $StaleGuestDays = 180
    )

    $cutoff = $AsOf.AddDays(-$StaleGuestDays)

    foreach ($user in $Snapshot.Users) {
        if ((Get-EsProperty -Object $user -Name 'userType' -Default 'Member') -ne 'Guest') { continue }
        if (-not (Get-EsProperty -Object $user -Name 'accountEnabled' -Default $false)) { continue }

        $upn        = Get-EsProperty -Object $user -Name 'userPrincipalName' -Default '(unknown upn)'
        $lastSignIn = Get-EsProperty -Object $user -Name 'lastSignInDateTime'

        if ($null -eq $lastSignIn) {
            $created = Get-EsProperty -Object $user -Name 'createdDateTime'
            if ($null -eq $created -or [datetime]$created -lt $cutoff) {
                New-EsFinding -RuleId 'guest-audit' -Severity Medium -Subject $upn `
                    -Detail 'Guest was invited but has never signed in.' `
                    -Recommendation 'Remove the guest; re-invite if collaboration resumes.'
            }
        }
        elseif ([datetime]$lastSignIn -lt $cutoff) {
            New-EsFinding -RuleId 'guest-audit' -Severity Medium -Subject $upn `
                -Detail ('Guest last signed in {0:yyyy-MM-dd}, more than {1} days ago.' -f [datetime]$lastSignIn, $StaleGuestDays) `
                -Recommendation 'Remove the guest account; external collaborators can be re-invited when needed.'
        }
    }
}
