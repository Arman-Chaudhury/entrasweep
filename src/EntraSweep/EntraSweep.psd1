@{
    RootModule        = 'EntraSweep.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '43bd8044-9857-487a-9978-7143d0731fa8'
    Author            = 'Arman Chaudhury'
    Copyright         = '(c) 2026 Arman Chaudhury. MIT License.'
    Description       = 'Identity-hygiene auditor for Microsoft Entra ID and on-prem Active Directory: offline-first snapshot audits, a rule pack for stale accounts / password policy / privileged-role sprawl, and HTML/JSON reports.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'Import-EsSnapshot'
        'Invoke-EsAudit'
        'Export-EsReport'
        'Export-EsHtmlReport'
        'Get-EsRuleRegistry'
        'Test-EsStaleAccount'
        'Test-EsPasswordExpiryDisabled'
        'Test-EsDormantLicensedAccount'
        'Test-EsGuestAccount'
        'Test-EsEmptyGroup'
        'Test-EsPrivilegedRoleSprawl'
        'Test-EsAdminMfaRegistration'
        'Test-EsAppCredentialExpiry'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('EntraID', 'ActiveDirectory', 'Identity', 'Security', 'Audit', 'Linux', 'Windows')
            ProjectUri = 'https://github.com/Arman-Chaudhury/entrasweep'
        }
    }
}
