#Requires -Version 7.2

# Dot-source everything; Private/ stays module-internal, Public/ and Rules/ export.
$folders = @('Private', 'Rules', 'Public')
$exported = [System.Collections.Generic.List[string]]::new()

foreach ($folder in $folders) {
    $path = Join-Path $PSScriptRoot $folder
    if (-not (Test-Path $path)) { continue }
    foreach ($file in Get-ChildItem -Path $path -Filter '*.ps1' | Sort-Object Name) {
        . $file.FullName
        if ($folder -ne 'Private') { $exported.Add($file.BaseName) }
    }
}

Export-ModuleMember -Function $exported
