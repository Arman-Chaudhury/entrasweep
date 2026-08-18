function Export-EsHtmlReport {
    <#
    .SYNOPSIS
        Writes findings to a self-contained single-file HTML dashboard:
        severity tiles, per-rule tables, and a client-side text filter.
        No external assets, so the file can be mailed or archived as-is.
    .EXAMPLE
        Invoke-EsAudit -SnapshotPath snap.json | Export-EsHtmlReport -Path report.html
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [pscustomobject[]] $Finding,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Title = 'EntraSweep report',

        [string] $Previous
    )

    begin {
        $all = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($item in $Finding) {
            if ($null -ne $item) { $all.Add($item) }
        }
    }
    end {
        $active   = @($all | Where-Object { -not (Test-EsFindingAccepted -Finding $_) })
        $accepted = @($all | Where-Object { Test-EsFindingAccepted -Finding $_ })

        $sevOrder = @{ High = 0; Medium = 1; Low = 2 }
        $encode = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }

        $css = @'
:root { color-scheme: light; }
* { box-sizing: border-box; }
body { margin: 0; padding: 2rem; font: 15px/1.5 -apple-system, "Segoe UI", Roboto, sans-serif; color: #1a2233; background: #f5f6f8; }
h1 { margin: 0 0 .25rem; font-size: 1.5rem; }
.meta { color: #5b6472; margin: 0 0 1.5rem; }
.tiles { display: flex; gap: 1rem; flex-wrap: wrap; margin-bottom: 1.5rem; }
.tile { background: #fff; border: 1px solid #e2e5ea; border-radius: 10px; padding: .9rem 1.4rem; min-width: 7.5rem; }
.tile .n { font-size: 1.7rem; font-weight: 700; }
.tile .l { color: #5b6472; font-size: .85rem; }
.tile.high .n { color: #b3261e; }
.tile.medium .n { color: #b26a00; }
.tile.low .n { color: #2b6cb0; }
#filter { width: 100%; max-width: 28rem; padding: .55rem .8rem; margin-bottom: 1.25rem; border: 1px solid #cfd4dc; border-radius: 8px; font: inherit; }
section.rule { background: #fff; border: 1px solid #e2e5ea; border-radius: 10px; padding: 1rem 1.25rem; margin-bottom: 1.25rem; }
section.rule h2 { margin: 0 0 .6rem; font-size: 1.05rem; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
section.rule h2 .count { color: #5b6472; font-weight: 400; font-size: .9rem; }
.tablewrap { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; padding: .45rem .6rem; border-top: 1px solid #eef0f3; vertical-align: top; }
th { color: #5b6472; font-size: .8rem; text-transform: uppercase; letter-spacing: .04em; border-top: none; }
.badge { display: inline-block; padding: .1rem .55rem; border-radius: 99px; font-size: .8rem; font-weight: 600; }
.badge.High { background: #fbe9e7; color: #b3261e; }
.badge.Medium { background: #fff3e0; color: #b26a00; }
.badge.Low { background: #e3f2fd; color: #2b6cb0; }
details.accepted { margin-top: 1.5rem; color: #5b6472; }
.empty { background: #fff; border: 1px dashed #cfd4dc; border-radius: 10px; padding: 2rem; text-align: center; color: #5b6472; }
'@

        $js = @'
document.getElementById("filter").addEventListener("input", function () {
  var q = this.value.toLowerCase();
  document.querySelectorAll("section.rule tbody tr").forEach(function (tr) {
    tr.style.display = tr.textContent.toLowerCase().indexOf(q) >= 0 ? "" : "none";
  });
});
'@

        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine('<!doctype html><html lang="en"><head><meta charset="utf-8">')
        [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
        [void]$sb.AppendLine('<title>' + (& $encode $Title) + '</title>')
        [void]$sb.AppendLine('<style>' + $css + '</style></head><body>')
        [void]$sb.AppendLine('<h1>' + (& $encode $Title) + '</h1>')
        $metaLine = 'Generated ' + [datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm') + ' UTC &middot; ' + $active.Count + ' active finding(s), ' + $accepted.Count + ' accepted'
        if ($Previous) {
            $delta = Get-EsReportDelta -Active $active -PreviousPath $Previous
            $metaLine += ' &middot; since previous: ' + $delta.NewCount + ' new, ' + $delta.ResolvedCount + ' resolved'
        }
        [void]$sb.AppendLine('<p class="meta">' + $metaLine + '</p>')

        [void]$sb.AppendLine('<div class="tiles">')
        foreach ($sev in @('High', 'Medium', 'Low')) {
            $count = @($active | Where-Object Severity -EQ $sev).Count
            [void]$sb.AppendLine('<div class="tile ' + $sev.ToLower() + '"><div class="n">' + $count + '</div><div class="l">' + $sev + '</div></div>')
        }
        [void]$sb.AppendLine('<div class="tile"><div class="n">' + $active.Count + '</div><div class="l">Total active</div></div>')
        [void]$sb.AppendLine('</div>')

        if ($active.Count -eq 0) {
            [void]$sb.AppendLine('<div class="empty">No active findings. Clean sweep.</div>')
        }
        else {
            [void]$sb.AppendLine('<input id="filter" type="search" placeholder="Filter findings&hellip;">')
            foreach ($group in ($active | Group-Object -Property RuleId | Sort-Object -Property Name)) {
                [void]$sb.AppendLine('<section class="rule"><h2>' + (& $encode $group.Name) + ' <span class="count">' + $group.Count + ' finding(s)</span></h2>')
                [void]$sb.AppendLine('<div class="tablewrap"><table><thead><tr><th>Severity</th><th>Subject</th><th>Detail</th><th>Recommendation</th></tr></thead><tbody>')
                foreach ($f in ($group.Group | Sort-Object -Property @{ Expression = { $sevOrder[$_.Severity] } }, Subject)) {
                    [void]$sb.AppendLine('<tr><td><span class="badge ' + $f.Severity + '">' + $f.Severity + '</span></td><td>' +
                        (& $encode $f.Subject) + '</td><td>' + (& $encode $f.Detail) + '</td><td>' + (& $encode $f.Recommendation) + '</td></tr>')
                }
                [void]$sb.AppendLine('</tbody></table></div></section>')
            }
        }

        if ($accepted.Count -gt 0) {
            [void]$sb.AppendLine('<details class="accepted"><summary>' + $accepted.Count + ' accepted (baselined) finding(s)</summary><div class="tablewrap"><table><thead><tr><th>Rule</th><th>Severity</th><th>Subject</th><th>Detail</th></tr></thead><tbody>')
            foreach ($f in $accepted) {
                [void]$sb.AppendLine('<tr><td>' + (& $encode $f.RuleId) + '</td><td>' + $f.Severity + '</td><td>' + (& $encode $f.Subject) + '</td><td>' + (& $encode $f.Detail) + '</td></tr>')
            }
            [void]$sb.AppendLine('</tbody></table></div></details>')
        }

        [void]$sb.AppendLine('<script>' + $js + '</script></body></html>')

        Set-Content -Path $Path -Value $sb.ToString() -Encoding utf8
        Write-Verbose "Wrote HTML report ($($active.Count) active finding(s)) to $Path"
    }
}
