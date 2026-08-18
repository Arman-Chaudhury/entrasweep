function Test-EsPrivilegedRoleSprawl {
    <#
    .SYNOPSIS
        Rule 'privileged-sprawl': privileged directory roles whose membership
        exceeds a cap. Many Global Administrators means a wide blast radius.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Snapshot,
        [ValidateRange(1, 1000)] [int] $MaxMembers = 5,
        [string[]] $PrivilegedRole = @('Global Administrator', 'Privileged Role Administrator')
    )

    foreach ($role in $Snapshot.DirectoryRoles) {
        $name = Get-EsProperty -Object $role -Name 'displayName' -Default '(unknown role)'
        if ($name -notin $PrivilegedRole) { continue }

        $membersProp = $role.PSObject.Properties['members']
        if ($null -eq $membersProp -or $null -eq $membersProp.Value) { continue }

        $count = @($membersProp.Value).Count
        if ($count -gt $MaxMembers) {
            New-EsFinding -RuleId 'privileged-sprawl' -Severity High -Subject $name `
                -Detail ('Role has {0} members, above the cap of {1}.' -f $count, $MaxMembers) `
                -Recommendation 'Move day-to-day work to lesser roles or PIM-style just-in-time elevation; keep standing membership minimal.'
        }
    }
}
