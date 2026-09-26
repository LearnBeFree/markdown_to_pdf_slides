# Build slides:  .\build.ps1 [source.md]
# Requires: pandoc, typst. No hardcoded absolute paths (everything is derived
# from this script's location, so the theme is portable).
#
# Outputs <name>.typ and <name>.pdf next to the SOURCE markdown file.
param([string]$Src = "example.md")

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Resolve the source to an absolute path (relative to the caller's cwd).
$SrcAbs = if ([System.IO.Path]::IsPathRooted($Src)) { $Src } else { Join-Path (Get-Location) $Src }

if (-not (Test-Path $SrcAbs)) {
    Write-Error "Source not found: $Src"
    exit 1
}

# Work inside the theme directory so --font-path and cwd-relative asset
# references resolve consistently; outputs still go next to the source.
Set-Location $ScriptDir

$SrcDir = Split-Path -Parent $SrcAbs
$Base = [System.IO.Path]::GetFileNameWithoutExtension($SrcAbs)
$Typ = Join-Path $SrcDir "$Base.typ"
$Pdf = Join-Path $SrcDir "$Base.pdf"

$FontArgs = @()
if (Test-Path (Join-Path $ScriptDir "fonts")) {
    $FontArgs = @("--font-path", (Join-Path $ScriptDir "fonts"))
}

# Extension tweaks:
#   -raw_tex                      keep `\word` sequences as literal text
#                                 instead of silently dropping raw TeX
#   +wikilinks_title_after_pipe   Obsidian `![[pic.png]]` embeds become real
#                                 images the filter can lay out
$env:THEME_DIR = $ScriptDir -replace '\\', '/'
pandoc $SrcAbs `
    --from markdown-raw_tex+wikilinks_title_after_pipe `
    --to typst `
    --standalone `
    --template (Join-Path $ScriptDir "template.typ") `
    --lua-filter (Join-Path $ScriptDir "theme-filters.lua") `
    --output $Typ
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# The filter emits absolute image paths and the .typ can live anywhere, so
# compile against the source file's drive root (images on other drives would
# need a wider root; theme-dir lets the import resolve regardless).
$Root = [System.IO.Path]::GetPathRoot($SrcAbs)
typst compile --root $Root @FontArgs $Typ $Pdf
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Built: $Pdf"
