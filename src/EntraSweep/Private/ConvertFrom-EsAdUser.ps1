function ConvertFrom-EsAdUser {
    <#
    .SYNOPSIS
        Maps one on-prem AD user (live object or CSV row) into the snapshot
        user schema: lastLogonTimestamp (FILETIME) or LastLogonDate become
        lastSignInDateTime, PasswordNeverExpires becomes passwordPolicies.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Row
    )

    $parseBool = {
        param($value)
        if ($null -eq $value -or [string]$value -eq '') { return $false }
        if ($value -is [bool]) { return $value }
        return [bool]::Parse([string]$value)
    }

    $parseDate = {
        param($value)
        if ($null -eq $value -or [string]$value -eq '') { return $null }
        if ($value -is [datetime]) { return $value.ToUniversalTime().ToString('o') }
        return [datetime]::Parse([string]$value, [cultureinfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime().ToString('o')
    }

    $lastSignIn = $null
    $fileTime = Get-EsProperty -Object $Row -Name 'lastLogonTimestamp'
    if ($null -ne $fileTime -and [string]$fileTime -ne '') {
        $lastSignIn = [datetime]::FromFileTimeUtc([int64]$fileTime).ToString('o')
    }
    else {
        $lastSignIn = & $parseDate (Get-EsProperty -Object $Row -Name 'LastLogonDate')
    }

    $upn = [string](Get-EsProperty -Object $Row -Name 'UserPrincipalName' -Default '')
    if ($upn -eq '') { $upn = [string](Get-EsProperty -Object $Row -Name 'SamAccountName' -Default '(unknown)') }

    $displayName = [string](Get-EsProperty -Object $Row -Name 'Name' -Default '')
    if ($displayName -eq '') { $displayName = $upn }

    $id = [string](Get-EsProperty -Object $Row -Name 'ObjectGUID' -Default '')
    if ($id -eq '') { $id = $upn }

    [pscustomobject]@{
        id                 = $id
        userPrincipalName  = $upn
        displayName        = $displayName
        accountEnabled     = & $parseBool (Get-EsProperty -Object $Row -Name 'Enabled')
        userType           = 'Member'
        createdDateTime    = & $parseDate (Get-EsProperty -Object $Row -Name 'whenCreated')
        lastSignInDateTime = $lastSignIn
        passwordPolicies   = if (& $parseBool (Get-EsProperty -Object $Row -Name 'PasswordNeverExpires')) {
            'DisablePasswordExpiration'
        } else { 'None' }
    }
}
