function Import-EsSnapshot {
    <#
    .SYNOPSIS
        Parses and validates a directory snapshot file (SPEC section 3).
    .DESCRIPTION
        A snapshot is a JSON export of directory state (from the Graph collector,
        an on-prem AD export, or a hand-written fixture). Only `users` is required;
        other collections default to empty. Unknown properties are ignored.
    .EXAMPLE
        Import-EsSnapshot -Path tests/fixtures/tenant-snapshot.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Snapshot file not found: $Path"
    }

    $raw = Get-Content -Path $Path -Raw | ConvertFrom-Json

    if ($null -eq (Get-EsProperty -Object $raw -Name 'users')) {
        throw "Snapshot '$Path' is missing the required 'users' collection."
    }

    $capturedAt = Get-EsProperty -Object $raw -Name 'capturedAt'

    [pscustomobject]@{
        Path              = (Resolve-Path -Path $Path).Path
        Source            = Get-EsProperty -Object $raw -Name 'source' -Default 'unknown'
        CapturedAt        = if ($capturedAt) { [datetime]$capturedAt } else { $null }
        Users             = @(Get-EsProperty -Object $raw -Name 'users' -Default @())
        Groups            = @(Get-EsProperty -Object $raw -Name 'groups' -Default @())
        DirectoryRoles    = @(Get-EsProperty -Object $raw -Name 'directoryRoles' -Default @())
        ServicePrincipals = @(Get-EsProperty -Object $raw -Name 'servicePrincipals' -Default @())
    }
}
