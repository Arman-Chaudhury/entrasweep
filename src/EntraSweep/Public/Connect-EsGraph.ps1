function Connect-EsGraph {
    <#
    .SYNOPSIS
        Signs in to Microsoft Graph with the OAuth2 device-code flow using a
        well-known public client, requesting only read scopes. The access
        token is kept in module state for Export-EsGraphSnapshot.
    .NOTES
        No secrets are stored: the token lives in memory for this session only.
        The default ClientId is Microsoft's "Microsoft Graph Command Line
        Tools" public client.
    #>
    [CmdletBinding()]
    param(
        [string] $TenantId = 'organizations',

        [string] $ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e',

        [string[]] $Scope = @(
            'User.Read.All'
            'Directory.Read.All'
            'AuditLog.Read.All'
            'Application.Read.All'
            'UserAuthenticationMethod.Read.All'
        ),

        [ValidateRange(60, 3600)]
        [int] $TimeoutSeconds = 900
    )

    $authBase = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0"
    $device = Invoke-RestMethod -Method Post -Uri "$authBase/devicecode" -Body @{
        client_id = $ClientId
        scope     = ($Scope -join ' ')
    }

    # e.g. "To sign in, use a web browser to open https://microsoft.com/devicelogin ..."
    Write-Output $device.message

    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([datetime]::UtcNow -lt $deadline) {
        Start-Sleep -Seconds ([int]$device.interval)
        try {
            $token = Invoke-RestMethod -Method Post -Uri "$authBase/token" -Body @{
                grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
                client_id   = $ClientId
                device_code = $device.device_code
            }
            $script:EsGraphAccessToken = $token.access_token
            Write-Output 'Connected to Microsoft Graph.'
            return
        }
        catch {
            $detail = ''
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
            if ($detail -match 'authorization_pending' -or $detail -match 'slow_down') { continue }
            throw
        }
    }
    throw "Device-code sign-in timed out after $TimeoutSeconds seconds."
}
