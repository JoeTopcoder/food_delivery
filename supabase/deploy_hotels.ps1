<#
Deploy Hotels & Travel Supabase functions and run migrations.

Usage:
  .\deploy_hotels.ps1 -ProjectRef <your-project-ref>

#>
param(
  [string]$ProjectRef = $env:SUPABASE_PROJECT_REF
)

if (-not $ProjectRef) {
  Write-Error "Project ref is required. Pass -ProjectRef or set SUPABASE_PROJECT_REF env var."
  exit 1
}

Write-Output "Applying DB migrations..."
cd (Split-Path -Path $MyInvocation.MyCommand.Path -Parent)
cd ..\supabase
supabase db push --project-ref $ProjectRef

Write-Output "Deploying Edge Functions (hotelbeds-*)..."
cd functions
$funcs = @(
  'hotelbeds-search',
  'hotelbeds-get-hotel-content',
  'hotelbeds-check-rate',
  'hotelbeds-create-booking',
  'hotelbeds-get-booking',
  'hotelbeds-cancel-booking',
  'hotelbeds-generate-voucher'
)
foreach ($f in $funcs) {
  Write-Output "Deploying $f"
  supabase functions deploy $f --project-ref $ProjectRef
}

Write-Output "Remember to set secrets: HOTELBEDS_API_KEY and HOTELBEDS_SECRET"
Write-Output "Example: supabase secrets set HOTELBEDS_API_KEY=... HOTELBEDS_SECRET=... --project-ref $ProjectRef"
