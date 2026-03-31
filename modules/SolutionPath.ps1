Write-Host ''
Write-Host ("  " + [string]([char]0x2500) * 68) -ForegroundColor DarkGray
Write-Host '  Package to Deploy' -ForegroundColor Cyan
Write-Host ("  " + [string]([char]0x2500) * 68) -ForegroundColor DarkGray
Write-Host ''
Write-Host '  Default package path:' -ForegroundColor White
Write-Host "    $packagePath" -ForegroundColor Yellow
Write-Host ''
Write-Host '  [Enter]   Use default path above' -ForegroundColor DarkGray
Write-Host '  [Path]    Type a different .sppkg file path' -ForegroundColor DarkGray
Write-Host ''

$packageName = "";
$pkgInput = (Read-Host '  Package path (or Enter for default)').Trim()
if ($pkgInput) { $packagePath = $pkgInput }

if ([System.IO.Path]::GetExtension($packagePath).ToLower() -ne '.sppkg') {
    Write-Host "  !! File must have a .sppkg extension: $packagePath" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $packagePath)) {
    Write-Host "  !! Package file not found: $packagePath" -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host "  Package  : $packagePath" -ForegroundColor Green

# Extract just the filename without extension for logging and display purposes — the full path is too noisy.
$packageName = [System.IO.Path]::GetFileNameWithoutExtension($packagePath)