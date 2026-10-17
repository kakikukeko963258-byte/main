param(
    [Parameter(Mandatory=$true)][string]$SourceIpa,
    [Parameter(Mandatory=$true)][string]$BridgeExe,
    [Parameter(Mandatory=$true)][string]$FileName
)
$ErrorActionPreference = 'Stop'
if ($FileName -notmatch '^[A-Za-z0-9._-]+\.ipa$') { throw 'IPA名が正しくありません。' }
$source = (Resolve-Path -LiteralPath $SourceIpa).Path
$worker = (Resolve-Path -LiteralPath $BridgeExe).Path
$approved = Join-Path $env:LOCALAPPDATA 'AltServerDirectIPA\Remote\ApprovedIPAs'
if (!(Test-Path -LiteralPath $approved -PathType Container)) { throw '改造版AltForge Remoteを先に設定してください。' }
$destination = Join-Path $approved $FileName
if (Test-Path -LiteralPath $destination) { throw '同名のIPAがあります。別名を指定してください。' }
$privateFolder = Join-Path $env:LOCALAPPDATA 'PCFileBridge\Enrollment'
[IO.Directory]::CreateDirectory($privateFolder) | Out-Null
$temporarySetup = Join-Path $privateFolder ([Guid]::NewGuid().ToString('N') + '.json')
$completed = $false
try {
    $arguments = '--export-connection "' + $temporarySetup + '"'
    $process = Start-Process -FilePath $worker -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if (!$process.WaitForExit(12000)) { $process.Kill(); throw '起動中のPC File Bridgeから設定を取得できませんでした。' }
    if ($process.ExitCode -ne 0) { throw 'PC File Bridgeを起動してから再実行してください。' }
    $setup = Get-Content -LiteralPath $temporarySetup -Raw | ConvertFrom-Json
    if ($setup.version -ne 1 -or [DateTimeOffset]$setup.expiresUtc -le [DateTimeOffset]::UtcNow) { throw '初回設定が期限切れです。' }
    Copy-Item -LiteralPath $source -Destination $destination
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($destination, [IO.Compression.ZipArchiveMode]::Update)
    try {
        if (!$archive.GetEntry('Payload/main.app/Info.plist')) { throw 'mainアプリのIPAではありません。' }
        $entryPath = 'Payload/main.app/PCFileBridgeSetup.json'
        $existing = $archive.GetEntry($entryPath)
        if ($existing) { $existing.Delete() }
        $entry = $archive.CreateEntry($entryPath)
        $stream = $entry.Open()
        try { $bytes = [IO.File]::ReadAllBytes($temporarySetup); $stream.Write($bytes, 0, $bytes.Length) }
        finally { $stream.Dispose() }
    } finally { $archive.Dispose() }
    $python = (Get-Command python -ErrorAction Stop).Source
    & $python (Join-Path $PSScriptRoot 'prepare-file-provider-signing.py') $destination
    if ($LASTEXITCODE -ne 0) { throw 'Files拡張の署名先設定を用意できませんでした。' }
    $completed = $true
    Write-Output '初回設定付きIPAをAltForge Remoteの許可済み一覧に用意しました。'
} finally {
    if (Test-Path -LiteralPath $temporarySetup) { Remove-Item -LiteralPath $temporarySetup }
    if (!$completed -and (Test-Path -LiteralPath $destination)) { Remove-Item -LiteralPath $destination }
}
