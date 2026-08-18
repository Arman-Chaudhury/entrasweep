function Test-EsEmptyGroup {
    <#
    .SYNOPSIS
        Rule 'empty-group': groups with an explicitly empty membership list.
        Groups whose snapshot omits membership entirely are skipped - absent
        data means "not collected", not "empty".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Snapshot
    )

    foreach ($group in $Snapshot.Groups) {
        # Deliberate direct property access: Get-EsProperty cannot distinguish
        # an absent 'members' key from a present-but-empty array (empty arrays
        # unroll to AutomationNull through a function return).
        $membersProp = $group.PSObject.Properties['members']
        if ($null -eq $membersProp -or $null -eq $membersProp.Value) { continue }

        if (@($membersProp.Value).Count -eq 0) {
            $name = Get-EsProperty -Object $group -Name 'displayName' -Default '(unnamed group)'
            New-EsFinding -RuleId 'empty-group' -Severity Low -Subject $name `
                -Detail 'Group has no members.' `
                -Recommendation 'Delete the group, or document why an empty group must remain (e.g. licensing shell).'
        }
    }
}
