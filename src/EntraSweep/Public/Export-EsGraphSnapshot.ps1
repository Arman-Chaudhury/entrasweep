function Export-EsGraphSnapshot {
    <#
    .SYNOPSIS
        Collects a schema-v1 snapshot from Microsoft Graph (read-only) and
        writes it to a JSON file ready for Invoke-EsAudit.
    .DESCRIPTION
        Requires Connect-EsGraph first, or an -AccessToken. The MFA
        registration report needs an Entra ID premium license; when the call
        fails the snapshot simply omits mfaRegistered and the admin-no-mfa
        rule skips those users.
    .EXAMPLE
        Connect-EsGraph
        Export-EsGraphSnapshot -OutFile tenant.json
        Invoke-EsAudit -SnapshotPath tenant.json | Export-EsHtmlReport -Path report.html
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $OutFile,

        [string] $AccessToken,

        [switch] $SkipMfaReport,

        [switch] $SkipGroupMembers
    )

    $token = if ($AccessToken) { $AccessToken } else { $script:EsGraphAccessToken }
    if (-not $token) {
        throw 'No Graph token available. Run Connect-EsGraph first, or pass -AccessToken.'
    }

    $header = @{ Authorization = "Bearer $token" }
    $base = 'https://graph.microsoft.com/v1.0'

    Write-Verbose 'Collecting users...'
    $rawUsers = Invoke-EsGraphRequest -Header $header -Uri (
        "$base/users?`$select=id,userPrincipalName,displayName,accountEnabled,userType," +
        'createdDateTime,signInActivity,passwordPolicies,assignedLicenses')

    $mfaById = @{}
    if (-not $SkipMfaReport) {
        try {
            Write-Verbose 'Collecting MFA registration report...'
            $mfaRows = Invoke-EsGraphRequest -Header $header -Uri (
                "$base/reports/authenticationMethods/userRegistrationDetails?`$select=id,isMfaRegistered")
            foreach ($row in $mfaRows) { $mfaById[[string]$row.id] = $row.isMfaRegistered }
        }
        catch {
            Write-Warning "MFA registration report unavailable (premium license or scope missing); the admin-no-mfa rule will skip. $($_.Exception.Message)"
        }
    }

    $users = @(foreach ($u in $rawUsers) {
            $signInActivity = Get-EsProperty -Object $u -Name 'signInActivity'
            $lastSignIn = if ($signInActivity) {
                Get-EsProperty -Object $signInActivity -Name 'lastSignInDateTime'
            } else { $null }

            $mapped = [pscustomobject]@{
                id                 = $u.id
                userPrincipalName  = $u.userPrincipalName
                displayName        = $u.displayName
                accountEnabled     = $u.accountEnabled
                userType           = Get-EsProperty -Object $u -Name 'userType' -Default 'Member'
                createdDateTime    = Get-EsProperty -Object $u -Name 'createdDateTime'
                lastSignInDateTime = $lastSignIn
                passwordPolicies   = Get-EsProperty -Object $u -Name 'passwordPolicies' -Default 'None'
                assignedLicenses   = @(Get-EsProperty -Object $u -Name 'assignedLicenses' -Default @())
            }
            if ($mfaById.ContainsKey([string]$u.id)) {
                $mapped | Add-Member -NotePropertyName mfaRegistered -NotePropertyValue $mfaById[[string]$u.id]
            }
            $mapped
        })

    Write-Verbose 'Collecting groups...'
    $rawGroups = Invoke-EsGraphRequest -Header $header -Uri "$base/groups?`$select=id,displayName"
    $groups = @(foreach ($g in $rawGroups) {
            $mapped = [pscustomobject]@{ id = $g.id; displayName = $g.displayName }
            if (-not $SkipGroupMembers) {
                $members = Invoke-EsGraphRequest -Header $header -Uri "$base/groups/$($g.id)/members?`$select=id"
                $mapped | Add-Member -NotePropertyName members -NotePropertyValue @(@($members) | ForEach-Object { $_.id })
            }
            $mapped
        })

    Write-Verbose 'Collecting directory roles...'
    $rawRoles = Invoke-EsGraphRequest -Header $header -Uri "$base/directoryRoles?`$select=id,displayName"
    $roles = @(foreach ($r in $rawRoles) {
            $members = Invoke-EsGraphRequest -Header $header -Uri "$base/directoryRoles/$($r.id)/members?`$select=id"
            [pscustomobject]@{
                displayName = $r.displayName
                members     = @(@($members) | ForEach-Object { $_.id })
            }
        })

    Write-Verbose 'Collecting service principals...'
    $servicePrincipals = @(Invoke-EsGraphRequest -Header $header -Uri (
            "$base/servicePrincipals?`$select=id,displayName,keyCredentials,passwordCredentials"))

    $snapshot = [pscustomobject]@{
        schemaVersion     = 1
        capturedAt        = [datetime]::UtcNow.ToString('o')
        source            = 'graph'
        users             = $users
        groups            = $groups
        directoryRoles    = $roles
        servicePrincipals = $servicePrincipals
    }

    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -Path $OutFile -Encoding utf8
    Write-Output ("Snapshot written to {0}: {1} users, {2} groups, {3} roles, {4} service principals." -f
        $OutFile, $users.Count, $groups.Count, $roles.Count, $servicePrincipals.Count)
}
