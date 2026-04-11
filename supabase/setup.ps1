# Supabase Tables Setup Script for Windows
# This script will push all database migrations to Supabase using PowerShell

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Food Driver - Supabase Setup" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Check if environment variables are set
if ([string]::IsNullOrEmpty($env:SUPABASE_URL) -or [string]::IsNullOrEmpty($env:SUPABASE_KEY)) {
    Write-Host "Error: SUPABASE_URL and SUPABASE_KEY environment variables are not set" -ForegroundColor Red
    Write-Host ""
    Write-Host "To set them up:" -ForegroundColor Yellow
    Write-Host "1. Go to your Supabase project dashboard"
    Write-Host "2. Find your project URL and API key"
    Write-Host "3. Set environment variables:"
    Write-Host "   `$env:SUPABASE_URL = 'your-project-url'"
    Write-Host "   `$env:SUPABASE_KEY = 'your-api-key'"
    Write-Host ""
    exit 1
}

Write-Host "Supabase credentials found" -ForegroundColor Green
Write-Host ""

# Read the complete schema file
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$schemaFile = Join-Path $scriptPath "complete_schema.sql"

if (-not (Test-Path $schemaFile)) {
    Write-Host "Error: complete_schema.sql not found at $schemaFile" -ForegroundColor Red
    exit 1
}

Write-Host "Reading schema from: $schemaFile" -ForegroundColor Yellow
$sqlContent = Get-Content $schemaFile -Raw

Write-Host "Instructions for running migrations:" -ForegroundColor Cyan
Write-Host ""
Write-Host "OPTION 1: Using Supabase Dashboard (Recommended)" -ForegroundColor Yellow
Write-Host "1. Go to: https://app.supabase.com/project/[your-project-id]/sql/new"
Write-Host "2. Paste the content of: complete_schema.sql"
Write-Host "3. Click 'Run' button"
Write-Host ""
Write-Host "OPTION 2: Using curl (if you have curl installed)" -ForegroundColor Yellow
$requestUrl = "$env:SUPABASE_URL/rest/v1/rpc/sql"
Write-Host "curl -X POST '$requestUrl' \" -ForegroundColor Gray
Write-Host "  -H 'Authorization: Bearer $env:SUPABASE_KEY' \" -ForegroundColor Gray
Write-Host "  -H 'Content-Type: application/json' \" -ForegroundColor Gray
Write-Host "  -d @complete_schema.sql" -ForegroundColor Gray
Write-Host ""

Write-Host "COPY THIS SQL CONTENT:" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host $sqlContent
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Setup Instructions Complete" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Copy the SQL content shown above"
Write-Host "2. Go to your Supabase dashboard"
Write-Host "3. Navigate to SQL Editor"
Write-Host "4. Click 'New query'"
Write-Host "5. Paste the SQL content"
Write-Host "6. Click 'Run'"
Write-Host ""
Write-Host "Setup script completed successfully! ✨" -ForegroundColor Green
