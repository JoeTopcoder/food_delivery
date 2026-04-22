$svc = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InloYXJ3ZWxpcnVlbWpleG11dXhuIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTQ0MDUxOCwiZXhwIjoyMDkxMDE2NTE4fQ.v-PMGcTny7Nz5PhPCbi6eZfpFJPwRk6eHMTnZEi6KH8"
$base = "https://yharweliruemjexmuuxn.supabase.co/rest/v1"
$h = @{apikey=$svc;Authorization="Bearer $svc";"Content-Type"="application/json";"Prefer"="return=minimal"}
function Patch-Order($id, $status) {
  try {
    $body = '{"status":"' + $status + '"}'
    $r = Invoke-WebRequest -Uri "$base/orders?id=eq.$id" -Method PATCH -Headers $h -Body $body -UseBasicParsing -ErrorAction Stop
    Write-Output "  $status -> $($r.StatusCode)"
  } catch { Write-Output "  $status -> ERROR: $($_.Exception.Message)" }
  Start-Sleep -Seconds 1
}
Write-Output "=== ORDER 1: ef242d06 ==="
Patch-Order "ef242d06-b123-4b97-b3ba-3797e9ce8fda" "confirmed"
Patch-Order "ef242d06-b123-4b97-b3ba-3797e9ce8fda" "preparing"
Patch-Order "ef242d06-b123-4b97-b3ba-3797e9ce8fda" "out_for_delivery"
Patch-Order "ef242d06-b123-4b97-b3ba-3797e9ce8fda" "delivered"
Write-Output "=== ORDER 2: 1a9fd986 ==="
Patch-Order "1a9fd986-2865-4c26-990c-1f97515b8e26" "confirmed"
Patch-Order "1a9fd986-2865-4c26-990c-1f97515b8e26" "preparing"
Patch-Order "1a9fd986-2865-4c26-990c-1f97515b8e26" "out_for_delivery"
Patch-Order "1a9fd986-2865-4c26-990c-1f97515b8e26" "delivered"
Write-Output "=== Latest notifications ==="
$n = Invoke-RestMethod "$base/notifications?select=title,type,created_at&order=created_at.desc&limit=10" -Headers @{apikey=$svc;Authorization="Bearer $svc"}
$n | ForEach-Object { Write-Output "$($_.created_at.Substring(11,8)) | $($_.type): $($_.title)" }
