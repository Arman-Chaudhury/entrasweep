function Invoke-EsGraphRequest {
    <#
    .SYNOPSIS
        Paged GET against Microsoft Graph: follows @odata.nextLink and retries
        on 429/5xx honoring Retry-After.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [hashtable] $Header,
        [ValidateRange(0, 10)] [int] $MaxRetry = 5
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $next = $Uri

    while ($next) {
        $attempt = 0
        $response = $null
        while ($true) {
            try {
                $response = Invoke-RestMethod -Uri $next -Headers $Header -Method Get
                break
            }
            catch [Microsoft.PowerShell.Commands.HttpResponseException] {
                $status = [int]$_.Exception.Response.StatusCode
                if (($status -eq 429 -or $status -ge 500) -and $attempt -lt $MaxRetry) {
                    $retryAfter = 2
                    $values = $null
                    if ($_.Exception.Response.Headers.TryGetValues('Retry-After', [ref]$values)) {
                        $retryAfter = [int](@($values)[0])
                    }
                    $attempt++
                    Write-Verbose "Graph returned $status for $next; retrying in ${retryAfter}s (attempt $attempt of $MaxRetry)"
                    Start-Sleep -Seconds $retryAfter
                    continue
                }
                throw
            }
        }

        if ($null -ne $response.PSObject.Properties['value']) {
            foreach ($item in @($response.value)) { $results.Add($item) }
        }
        else {
            $results.Add($response)
        }
        $next = Get-EsProperty -Object $response -Name '@odata.nextLink'
    }

    @($results)
}
