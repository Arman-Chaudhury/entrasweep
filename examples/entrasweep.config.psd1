@{
    # Keys are rule ids (Get-EsRuleRegistry); values map to the rule's
    # parameters. 'Enabled = $false' turns a rule off entirely.
    'stale-account'     = @{ StaleDays = 120 }
    'guest-audit'       = @{ StaleGuestDays = 365 }
    'privileged-sprawl' = @{ MaxMembers = 3 }
    'empty-group'       = @{ Enabled = $false }
}
