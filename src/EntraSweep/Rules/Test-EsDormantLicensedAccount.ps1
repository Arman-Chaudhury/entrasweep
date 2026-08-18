function Test-EsDormantLicensedAccount {
    <#
    .SYNOPSIS
        Rule 'dormant-licensed': licensed accounts that are disabled or have not
        signed in within the threshold - licenses that are likely wasted spend.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Snapshot,
        [datetime] $AsOf = [datetime]::UtcNow,
        [ValidateRange(1, 3650)] [int] $DormantDays = 60
    )

    $cutoff = $AsOf.AddDays(-$DormantDays)

    foreach ($user in $Snapshot.Users) {
        $licenses = @(Get-EsProperty -Object $user -Name 'assignedLicenses' -Default @())
        if ($licenses.Count -eq 0) { continue }

        $upn = Get-EsProperty -Object $user -Name 'userPrincipalName' -Default '(unknown upn)'

        if (-not (Get-EsProperty -Object $user -Name 'accountEnabled' -Default $false)) {
            New-EsFinding -RuleId 'dormant-licensed' -Severity Medium -Subject $upn `
                -Detail ('Disabled account still holds {0} license(s).' -f $licenses.Count) `
                -Recommendation 'Reclaim the license(s) as part of offboarding.'
            continue
        }

        $lastSignIn = Get-EsProperty -Object $user -Name 'lastSignInDateTime'
        if ($null -ne $lastSignIn) {
            if ([datetime]$lastSignIn -lt $cutoff) {
                New-EsFinding -RuleId 'dormant-licensed' -Severity Medium -Subject $upn `
                    -Detail ('Licensed account ({0} license(s)) last signed in {1:yyyy-MM-dd}, more than {2} days ago.' -f $licenses.Count, [datetime]$lastSignIn, $DormantDays) `
                    -Recommendation 'Reclaim the license(s) or confirm the account is returning to use.'
            }
        }
        else {
            $created = Get-EsProperty -Object $user -Name 'createdDateTime'
            if ($null -eq $created -or [datetime]$created -lt $cutoff) {
                New-EsFinding -RuleId 'dormant-licensed' -Severity Medium -Subject $upn `
                    -Detail ('Licensed account ({0} license(s)) has never signed in.' -f $licenses.Count) `
                    -Recommendation 'Reclaim the license(s) until the account is actually in use.'
            }
        }
    }
}
