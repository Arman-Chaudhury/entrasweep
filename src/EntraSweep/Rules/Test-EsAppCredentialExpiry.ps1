function Test-EsAppCredentialExpiry {
    <#
    .SYNOPSIS
        Rule 'app-credential-expiry': service-principal client secrets and
        certificates that are expired (High) or expiring soon (Medium).
        Expired credentials are how integrations break at 3am.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Snapshot,
        [datetime] $AsOf = [datetime]::UtcNow,
        [ValidateRange(1, 365)] [int] $ExpiryWindowDays = 30
    )

    $window = $AsOf.AddDays($ExpiryWindowDays)
    $credentialKinds = @(
        @{ Property = 'passwordCredentials'; Label = 'Client secret' }
        @{ Property = 'keyCredentials';      Label = 'Certificate' }
    )

    foreach ($sp in $Snapshot.ServicePrincipals) {
        $name = Get-EsProperty -Object $sp -Name 'displayName' -Default '(unnamed service principal)'

        foreach ($kind in $credentialKinds) {
            $credsProp = $sp.PSObject.Properties[$kind.Property]
            if ($null -eq $credsProp -or $null -eq $credsProp.Value) { continue }

            foreach ($cred in @($credsProp.Value)) {
                $end = Get-EsProperty -Object $cred -Name 'endDateTime'
                if ($null -eq $end) { continue }
                $endDate = [datetime]$end

                if ($endDate -lt $AsOf) {
                    New-EsFinding -RuleId 'app-credential-expiry' -Severity High -Subject $name `
                        -Detail ('{0} expired {1:yyyy-MM-dd}.' -f $kind.Label, $endDate) `
                        -Recommendation 'Rotate the credential and remove the expired entry; check whether anything silently broke.'
                }
                elseif ($endDate -lt $window) {
                    New-EsFinding -RuleId 'app-credential-expiry' -Severity Medium -Subject $name `
                        -Detail ('{0} expires {1:yyyy-MM-dd} (within {2} days).' -f $kind.Label, $endDate, $ExpiryWindowDays) `
                        -Recommendation 'Rotate the credential before it expires.'
                }
            }
        }
    }
}
