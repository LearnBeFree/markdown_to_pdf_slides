# Build slides:  .\build.ps1 [source.md]
# Requires: pandoc, typst. No hardcoded absolute paths (everything is derived
# from this script's location, so the theme is portable).
param([string]$Src = "example.md")

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Resolve the source to an absolute path (relative to the caller's cwd).
$SrcAbs = if ([System.IO.Path]::IsPathRooted($Src)) { $Src } else { Join-Path (Get-Location) $Src }

if (-not (Test-Path $SrcAbs)) {
    Write-Error "Source not found: $Src"
    exit 1
}

# Work inside the theme directory so the generated .typ can import
# art-theme.typ, and so --font-path / assets resolve consistently.
Set-Location $ScriptDir

$Base = [System.IO.Path]::GetFileNameWithoutExtension($SrcAbs)
$Typ = "$Base.typ"
$Pdf = "$Base.pdf"

$FontArgs = @()
if (Test-Path (Join-Path $ScriptDir "fonts")) {
    $FontArgs = @("--font-path", (Join-Path $ScriptDir "fonts"))
}

pandoc $SrcAbs `
    --from markdown `
    --to typst `
    --standalone `
    --template (Join-Path $ScriptDir "template.typ") `
    --lua-filter (Join-Path $ScriptDir "theme-filters.lua") `
    --output $Typ
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Pandoc hardcodes a cramped `inset: <n>pt` on every table. Typst cannot
# override an explicit argument with a set-rule (and rebuilding the table in a
# show-rule recurses), so widen the cell padding in the generated file.
# Read/write as UTF-8 (no BOM) to keep Cyrillic text intact.
$utf8 = New-Object System.Text.UTF8Encoding($false)
$src = [System.IO.File]::ReadAllText((Resolve-Path $Typ), $utf8)
$src = [regex]::Replace($src, 'inset: [0-9.]+pt', 'inset: (x: 0.95em, y: 0.72em)')
[System.IO.File]::WriteAllText((Resolve-Path $Typ), $src, $utf8)

typst compile @FontArgs $Typ $Pdf
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Built: $(Join-Path $ScriptDir $Pdf)"
