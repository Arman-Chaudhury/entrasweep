function Test-EsStaleAccount {
    <#
    .SYNOPSIS
        Rule 'stale-account': enabled accounts whose last sign-in is older than
        the threshold. Accounts that have never signed in at all rate High.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Snapshot,
        [datetime] $AsOf = [datetime]::UtcNow,
        [ValidateRange(1, 3650)] [int] $StaleDays = 90
    )

    $cutoff = $AsOf.AddDays(-$StaleDays)

    foreach ($user in $Snapshot.Users) {
        if (-not (Get-EsProperty -Object $user -Name 'accountEnabled' -Default $false)) { continue }
        # Guest staleness has its own thresholds and remediation: see 'guest-audit'.
        if ((Get-EsProperty -Object $user -Name 'userType' -Default 'Member') -eq 'Guest') { continue }

        $upn        = Get-EsProperty -Object $user -Name 'userPrincipalName' -Default '(unknown upn)'
        $lastSignIn = Get-EsProperty -Object $user -Name 'lastSignInDateTime'

        if ($null -eq $lastSignIn) {
            # Never signed in: only flag once the account is old enough that
            # "new hire, hasn't started yet" stops being a plausible explanation.
            $created = Get-EsProperty -Object $user -Name 'createdDateTime'
            if ($null -eq $created -or [datetime]$created -lt $cutoff) {
                New-EsFinding -RuleId 'stale-account' -Severity High -Subject $upn `
                    -Detail 'Enabled account has never signed in.' `
                    -Recommendation 'Disable the account, or confirm it is an intentional break-glass/service identity and baseline it.'
            }
        }
        elseif ([datetime]$lastSignIn -lt $cutoff) {
            New-EsFinding -RuleId 'stale-account' -Severity Medium -Subject $upn `
                -Detail ('Enabled account last signed in {0:yyyy-MM-dd}, more than {1} days before {2:yyyy-MM-dd}.' -f [datetime]$lastSignIn, $StaleDays, $AsOf) `
                -Recommendation 'Review with the account owner; disable if no longer needed.'
        }
    }
}
