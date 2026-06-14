#!/usr/bin/env pwsh
# Build both web apps to their separate output directories.
# Usage: .\build_web.ps1 [restaurant|admin|both]
# Default builds both.

param(
    [string]$Target = "both"
)

$ErrorActionPreference = "Stop"

function Build-Restaurant {
    Write-Host "`n===> Building RESTAURANT web app..." -ForegroundColor Cyan
    flutter build web `
        --dart-define=WEB_MODE=restaurant `
        --output build/web_restaurant `
        --release
    Write-Host "===> Restaurant build complete -> build/web_restaurant/" -ForegroundColor Green
}

function Build-Admin {
    Write-Host "`n===> Building ADMIN web app..." -ForegroundColor Cyan
    flutter build web `
        --dart-define=WEB_MODE=admin `
        --output build/web_admin `
        --release
    Write-Host "===> Admin build complete -> build/web_admin/" -ForegroundColor Green
}

switch ($Target.ToLower()) {
    "restaurant" { Build-Restaurant }
    "admin"      { Build-Admin }
    default      { Build-Restaurant; Build-Admin }
}

Write-Host "`nDone!" -ForegroundColor Green
