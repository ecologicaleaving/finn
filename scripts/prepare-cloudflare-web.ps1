param([string]$Directory = 'build/web')

$ErrorActionPreference = 'Stop'
$workerPath = Join-Path $Directory 'flutter_service_worker.js'
$worker = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $workerPath))
$pattern = '(?s)(const RESOURCES = )(\{.*?\})(;)'
$match = [regex]::Match($worker, $pattern)
if (-not $match.Success) {
    throw 'Manifest offline Flutter non riconosciuto: verificare il formato prima del deploy.'
}
$resources = $match.Groups[2].Value | ConvertFrom-Json
foreach ($metadata in @('_headers', '_redirects', '.assetsignore')) {
    # Hosting metadata is not public content. The Nginx site returns 404 for it.
    # Requesting it in downloadOffline would fail the full offline preload.
    $resources.PSObject.Properties.Remove($metadata)
}
$json = $resources | ConvertTo-Json -Compress -Depth 8
$updated = $worker.Substring(0, $match.Index) +
    $match.Groups[1].Value + $json + $match.Groups[3].Value +
    $worker.Substring($match.Index + $match.Length)
[IO.File]::WriteAllText((Resolve-Path -LiteralPath $workerPath), $updated,
    (New-Object Text.UTF8Encoding($false)))
Write-Output 'Cache offline allineata agli asset pubblici del sito.'
