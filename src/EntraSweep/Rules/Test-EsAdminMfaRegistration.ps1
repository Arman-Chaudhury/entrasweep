function Test-EsAdminMfaRegistration {
    <#
    .SYNOPSIS
        Rule 'admin-no-mfa': members of privileged roles whose snapshot records
        mfaRegistered = false. Accounts with no mfaRegistered data are skipped -
        absent data means the authentication-methods report was not collected,
        not that MFA is missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Snapshot,
        [string[]] $PrivilegedRole = @('Global Administrator', 'Privileged Role Administrator')
    )

    $userById = @{}
    foreach ($user in $Snapshot.Users) {
        $id = Get-EsProperty -Object $user -Name 'id'
        if ($null -ne $id) { $userById[[string]$id] = $user }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($role in $Snapshot.DirectoryRoles) {
        $roleName = Get-EsProperty -Object $role -Name 'displayName' -Default '(unknown role)'
        if ($roleName -notin $PrivilegedRole) { continue }

        $membersProp = $role.PSObject.Properties['members']
        if ($null -eq $membersProp -or $null -eq $membersProp.Value) { continue }

        foreach ($memberId in @($membersProp.Value)) {
            $user = $userById[[string]$memberId]
            if ($null -eq $user) { continue }
            if (-not (Get-EsProperty -Object $user -Name 'accountEnabled' -Default $false)) { continue }

            $mfaProp = $user.PSObject.Properties['mfaRegistered']
            if ($null -eq $mfaProp -or $null -eq $mfaProp.Value) { continue }
            if ($mfaProp.Value -eq $true) { continue }

            $upn = Get-EsProperty -Object $user -Name 'userPrincipalName' -Default '(unknown upn)'
            if (-not $seen.Add($upn)) { continue }

            New-EsFinding -RuleId 'admin-no-mfa' -Severity High -Subject $upn `
                -Detail ("Member of privileged role '{0}' is not registered for MFA." -f $roleName) `
                -Recommendation 'Require MFA registration for this account immediately, or remove it from the role.'
        }
    }
}
