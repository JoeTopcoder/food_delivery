# ====================================================================
# NCB PowerTranz Test Keys Setup Script
# This script runs the SQL to add NCB test credentials to your Supabase database
# ====================================================================

Write-Host "==============================================  " -ForegroundColor Cyan
Write-Host "  NCB PowerTranz Test Keys Setup" -ForegroundColor White
Write-Host "=============================================="  -ForegroundColor Cyan
Write-Host ""

# Check if .env file exists in supabase directory
$envFile = "$PSScriptRoot\.env"

if (Test-Path $envFile) {
    Write-Host "Found Supabase .env file" -ForegroundColor Green
    Write-Host ""
    
    # Read the SQL file
    $sqlFile = "$PSScriptRoot\seed_ncb_test_keys.sql"
    if (Test-Path $sqlFile) {
        Write-Host "SQL file found: $sqlFile" -ForegroundColor Green
        Write-Host ""
        Write-Host "To apply the NCB test keys, run:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  npx supabase db execute --file seed_ncb_test_keys.sql" -ForegroundColor White
        Write-Host ""
        Write-Host "Or manually run the SQL in:" -ForegroundColor Yellow
        Write-Host "  $sqlFile" -ForegroundColor White
        Write-Host ""
    } else {
        Write-Host "SQL file not found: $sqlFile" -ForegroundColor Red
    }
} else {
    Write-Host "Supabase .env file not found at: $envFile" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please ensure you have initialized Supabase locally:" -ForegroundColor Yellow
    Write-Host "  supabase init" -ForegroundColor White
    Write-Host ""
    Write-Host "And linked to your project:" -ForegroundColor Yellow
    Write-Host "  supabase link --project-ref YOUR_PROJECT_REF" -ForegroundColor White
    Write-Host ""
}

Write-Host "=============================================="  -ForegroundColor Cyan
Write-Host "  NCB Configuration Keys:" -ForegroundColor White
Write-Host "=============================================="  -ForegroundColor Cyan
Write-Host ""
Write-Host "  ncb_powertranz_id       - PowerTranz API ID" -ForegroundColor Gray
Write-Host "  ncb_powertranz_password - PowerTranz API Password" -ForegroundColor Gray
Write-Host "  ncb_merchant_id         - NCB Merchant ID" -ForegroundColor Gray
Write-Host "  ncb_use_sandbox         - Use sandbox (1) or production (0)" -ForegroundColor Gray
Write-Host "  ncb_enabled             - Enable NCB payments (1=enabled)" -ForegroundColor Gray
Write-Host ""
Write-Host "Note: The test values in seed_ncb_test_keys.sql are placeholders." -ForegroundColor Yellow
Write-Host "Replace them with actual credentials from NCB/PowerTranz." -ForegroundColor Yellow
Write-Host ""