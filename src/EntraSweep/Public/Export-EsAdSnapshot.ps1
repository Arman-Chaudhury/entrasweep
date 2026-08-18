function Export-EsAdSnapshot {
    <#
    .SYNOPSIS
        Builds a schema-v1 snapshot from on-premises Active Directory - either
        live via the ActiveDirectory (RSAT) module on a domain-joined Windows
        host, or portably from a CSV export produced elsewhere.
    .DESCRIPTION
        The CSV route works on any OS. Produce the export on any domain
        machine with:

        Get-ADUser -Filter * -Properties Enabled,whenCreated,lastLogonTimestamp,PasswordNeverExpires |
            Select-Object ObjectGUID,UserPrincipalName,SamAccountName,Name,Enabled,whenCreated,
                          @{n='lastLogonTimestamp';e={$_.lastLogonTimestamp}},PasswordNeverExpires |
            Export-Csv users.csv -NoTypeInformation

        Note: lastLogonTimestamp is replicated lazily by AD (up to 14 days
        behind), which is fine for stale-account thresholds of 60+ days.
        The v0.1 AD snapshot covers users only; groups and privileged-role
        data remain Graph-collector territory.
    .EXAMPLE
        Export-EsAdSnapshot -FromCsv users.csv -OutFile ad-snapshot.json
    .EXAMPLE
        Export-EsAdSnapshot -Live -OutFile ad-snapshot.json
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Live',
        Justification = 'Parameter-set selector; the set name drives the switch statement.')]
    [CmdletBinding(DefaultParameterSetName = 'Csv')]
    param(
        [Parameter(Mandatory)]
        [string] $OutFile,

        [Parameter(Mandatory, ParameterSetName = 'Csv')]
        [string] $FromCsv,

        [Parameter(Mandatory, ParameterSetName = 'Live')]
        [switch] $Live,

        [Parameter(ParameterSetName = 'Live')]
        [string] $Server
    )

    $rows = switch ($PSCmdlet.ParameterSetName) {
        'Csv' {
            if (-not (Test-Path -Path $FromCsv -PathType Leaf)) {
                throw "CSV export not found: $FromCsv"
            }
            @(Import-Csv -Path $FromCsv)
        }
        'Live' {
            if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
                throw 'The ActiveDirectory module (RSAT) is not available on this host. Run the export on a domain-joined Windows machine, or use -FromCsv (see help for the export one-liner).'
            }
            $adParams = @{
                Filter     = '*'
                Properties = @('Enabled', 'whenCreated', 'lastLogonTimestamp', 'PasswordNeverExpires', 'userPrincipalName')
            }
            if ($Server) { $adParams.Server = $Server }
            @(Get-ADUser @adParams)
        }
    }

    $users = @($rows | ForEach-Object { ConvertFrom-EsAdUser -Row $_ })

    $snapshot = [pscustomobject]@{
        schemaVersion     = 1
        capturedAt        = [datetime]::UtcNow.ToString('o')
        source            = 'ad-export'
        users             = $users
        groups            = @()
        directoryRoles    = @()
        servicePrincipals = @()
    }

    $snapshot | ConvertTo-Json -Depth 6 | Set-Content -Path $OutFile -Encoding utf8
    Write-Output ("Snapshot written to {0}: {1} users (source: ad-export)." -f $OutFile, $users.Count)
}
