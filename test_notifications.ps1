$svc = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InloYXJ3ZWxpcnVlbWpleG11dXhuIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTQ0MDUxOCwiZXhwIjoyMDkxMDE2NTE4fQ.v-PMGcTny7Nz5PhPCbi6eZfpFJPwRk6eHMTnZEi6KH8"
$base = "https://yharweliruemjexmuuxn.supabase.co/rest/v1"
$sh = @{ "apikey" = $svc; "Authorization" = "Bearer $svc"; "Content-Type" = "application/json"; "Prefer" = "return=minimal" }
$shGet = @{ "apikey" = $svc; "Authorization" = "Bearer $svc" }

# 1. Get user FCM token
$userId = "5a32ab4f-7270-4787-a0b0-0afd9cdda09f"
$orderId = "1a9fd986-2865-4c26-990c-1f97515b8e26"  # most recent pending order

$user = (Invoke-WebRequest "$base/users?select=id,email,fcm_token&id=eq.$userId" -Headers $shGet).Content | ConvertFrom-Json
Write-Host "User: $($user[0].email)"
$fcm = $user[0].fcm_token
if ($fcm) {
    Write-Host "FCM token: $($fcm.Substring(0, [Math]::Min(40, $fcm.Length)))..."
} else {
    Write-Host "NO FCM TOKEN - push will be skipped by trigger"
}

# 2. Update order status to 'confirmed'
Write-Host "`nUpdating order $orderId to 'confirmed'..."
$body = '{"status":"confirmed"}'
$resp = Invoke-WebRequest "$base/orders?id=eq.$orderId" -Method Patch -Headers $sh -Body $body
Write-Host "HTTP: $($resp.StatusCode)"

# 3. Wait 2 seconds for trigger to fire
Start-Sleep -Seconds 2

# 4. Check notifications table for new rows
Write-Host "`nChecking notifications table..."
$notifs = (Invoke-WebRequest "$base/notifications?select=title,body,type,created_at&order=created_at.desc&limit=5" -Headers $shGet).Content
Write-Host $notifs
