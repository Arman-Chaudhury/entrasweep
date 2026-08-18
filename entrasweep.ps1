#Requires -Version 7.2
<#
.SYNOPSIS
    One-shot sweep: audit a snapshot, write reports, and exit nonzero when
    posture regresses - the entry point for schedulers and CI gates.
.DESCRIPTION
    Wraps the EntraSweep module for unattended use. Exit code 0 means no
    active findings at or above -FailOn severity (or -FailOn not given);
    exit code 1 means the gate tripped.
.EXAMPLE
    ./entrasweep.ps1 -SnapshotPath snap.json -OutHtml report.html -FailOn High
.EXAMPLE
    ./entrasweep.ps1 -SnapshotPath snap.json -BaselinePath baseline.json -UpdateBaseline
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $SnapshotPath,

    [string[]] $Rule,

    [datetime] $AsOf = [datetime]::UtcNow,

    [string] $ConfigPath,

    [string] $BaselinePath,

    [string] $OutJson,

    [string] $OutHtml,

    [string] $OutCsv,

    [string] $Previous,

    [ValidateSet('High', 'Medium', 'Low')]
    [string] $FailOn,

    [switch] $UpdateBaseline
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src' 'EntraSweep' 'EntraSweep.psd1') -Force

$auditArgs = @{ SnapshotPath = $SnapshotPath; AsOf = $AsOf }
if ($Rule) { $auditArgs.Rule = $Rule }
if ($ConfigPath) { $auditArgs.ConfigPath = $ConfigPath }
if ($BaselinePath -and (Test-Path -Path $BaselinePath -PathType Leaf)) {
    $auditArgs.BaselinePath = $BaselinePath
}

$findings = @(Invoke-EsAudit @auditArgs)
$active = @($findings | Where-Object { -not $_.Accepted })

if ($UpdateBaseline) {
    if (-not $BaselinePath) { throw '-UpdateBaseline requires -BaselinePath.' }
    $entries = @($active | ForEach-Object { [ordered]@{ ruleId = $_.RuleId; subject = $_.Subject } })
    [pscustomobject]@{
        updatedAt = $AsOf.ToString('o')
        entries   = $entries
    } | ConvertTo-Json -Depth 4 | Set-Content -Path $BaselinePath -Encoding utf8
    Write-Output "Baseline updated: $($entries.Count) entries written to $BaselinePath"
    exit 0
}

if ($OutJson) {
    $splat = @{ Path = $OutJson }
    if ($Previous) { $splat.Previous = $Previous }
    $findings | Export-EsReport @splat
    Write-Output "JSON report: $OutJson"
}
if ($OutHtml) {
    $splat = @{ Path = $OutHtml }
    if ($Previous) { $splat.Previous = $Previous }
    $findings | Export-EsHtmlReport @splat
    Write-Output "HTML report: $OutHtml"
}
if ($OutCsv) {
    $findings | Export-EsCsvReport -Path $OutCsv
    Write-Output "CSV report: $OutCsv"
}

$acceptedCount = $findings.Count - $active.Count
Write-Output ("Active findings: {0} (accepted: {1})" -f $active.Count, $acceptedCount)
foreach ($sev in @('High', 'Medium', 'Low')) {
    $count = @($active | Where-Object Severity -EQ $sev).Count
    if ($count -gt 0) { Write-Output ("  {0}: {1}" -f $sev, $count) }
}

if ($FailOn) {
    $rank = @{ Low = 1; Medium = 2; High = 3 }
    $worst = 0
    foreach ($f in $active) {
        if ($rank[$f.Severity] -gt $worst) { $worst = $rank[$f.Severity] }
    }
    if ($worst -ge $rank[$FailOn]) {
        Write-Output "GATE FAILED: active findings at or above $FailOn severity."
        exit 1
    }
}

Write-Output 'Gate passed.'
exit 0
