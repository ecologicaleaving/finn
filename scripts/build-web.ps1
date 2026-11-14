param(
    [string]$Flutter = 'flutter',
    [string]$SourceEnv = '.env'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
$assetPath = Join-Path $projectRoot '.env'
$hadAsset = Test-Path -LiteralPath $assetPath
$originalAsset = if ($hadAsset) { [IO.File]::ReadAllBytes($assetPath) } else { $null }

try {
    $clientConfig = @{}
    if (Test-Path -LiteralPath $SourceEnv) {
        foreach ($line in [IO.File]::ReadAllLines((Resolve-Path -LiteralPath $SourceEnv))) {
            if ($line -match '^\s*(SUPABASE_URL|SUPABASE_ANON_KEY)\s*=\s*(.*?)\s*$') {
                $clientConfig[$matches[1]] = $matches[2].Trim('"', "'")
            }
        }
    }
    foreach ($name in @('SUPABASE_URL', 'SUPABASE_ANON_KEY')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { $clientConfig[$name] = $value }
        if (-not $clientConfig[$name] -or $clientConfig[$name] -match '[\r\n]') {
            throw "Configurare $name nell'ambiente o nel file SourceEnv."
        }
    }
    $anonKey = $clientConfig['SUPABASE_ANON_KEY']
    if ($anonKey.StartsWith('sb_secret_')) { throw 'La build web richiede una chiave pubblica Supabase.' }
    if ($anonKey.Split('.').Length -eq 3) {
        $payload = $anonKey.Split('.')[1].Replace('-', '+').Replace('_', '/')
        $payload = $payload.PadRight($payload.Length + (4 - $payload.Length % 4) % 4, '=')
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        if ($claims.role -ne 'anon') { throw 'Usare la anon key pubblica, mai service_role o token utente.' }
    } elseif (-not $anonKey.StartsWith('sb_publishable_')) {
        throw 'Formato della chiave pubblica Supabase non riconosciuto.'
    }
    # .env is a mobile Flutter asset. Only public client configuration may be bundled.
    $publicEnv = "SUPABASE_URL=$($clientConfig['SUPABASE_URL'])`nSUPABASE_ANON_KEY=$anonKey`n"
    [IO.File]::WriteAllText($assetPath, $publicEnv, (New-Object Text.UTF8Encoding($false)))
    & $Flutter build web --release --no-wasm-dry-run --pwa-strategy=offline-first --no-web-resources-cdn --dart-define-from-file=.env
    if ($LASTEXITCODE -ne 0) { throw "Build web fallita (exit $LASTEXITCODE)." }
    & (Join-Path $PSScriptRoot 'prepare-cloudflare-web.ps1')
    Write-Output 'Build web pronta in build/web (solo configurazione client pubblica).'
} finally {
    if ($hadAsset) { [IO.File]::WriteAllBytes($assetPath, $originalAsset) }
    elseif (Test-Path -LiteralPath $assetPath) { Remove-Item -LiteralPath $assetPath }
    Pop-Location
}
