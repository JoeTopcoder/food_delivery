$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$screenshotDir = "c:\Users\scott\Documents\Bank\food_driver\screenshots"

function Take-Shot($name) {
    Start-Sleep -Milliseconds 2500
    & $adb shell screencap -p /sdcard/ss.png 2>$null
    & $adb pull /sdcard/ss.png "$screenshotDir\$name.png" 2>$null | Out-Null
    Write-Host "  [OK] $name"
}

function Tap($x, $y) {
    & $adb shell input tap $x $y 2>$null
    Start-Sleep -Milliseconds 800
}

function Back() {
    & $adb shell input keyevent KEYCODE_BACK 2>$null
    Start-Sleep -Milliseconds 800
}

function Swipe-Up() {
    & $adb shell input swipe 540 1800 540 600 400 2>$null
    Start-Sleep -Milliseconds 500
}

function Swipe-Down() {
    & $adb shell input swipe 540 600 540 1800 400 2>$null
    Start-Sleep -Milliseconds 500
}

# Bottom nav positions (1080x2340 screen): Home, Grocery, Search, Orders, Profile
$navHome = @(72, 1420)
$navGrocery = @(216, 1420)
$navSearch = @(365, 1420)
$navOrders = @(510, 1420)
$navProfile = @(660, 1420)

Write-Host "=== Taking Customer Screenshots ==="

# 1. Home Screen
Write-Host "Home tab..."
Tap $navHome[0] $navHome[1]
Take-Shot "customer_01_home"
Swipe-Up
Take-Shot "customer_01b_home_scroll"

# 2. Grocery tab
Write-Host "Grocery tab..."
Tap $navGrocery[0] $navGrocery[1]
Take-Shot "customer_02_grocery"

# 3. Search tab
Write-Host "Search tab..."
Tap $navSearch[0] $navSearch[1]
Take-Shot "customer_03_search"

# 4. Orders tab
Write-Host "Orders tab..."
Tap $navOrders[0] $navOrders[1]
Take-Shot "customer_04_orders"

# 5. Profile tab
Write-Host "Profile tab..."
Tap $navProfile[0] $navProfile[1]
Take-Shot "customer_05_profile"
Swipe-Up
Take-Shot "customer_05b_profile_scroll"

# Scroll back up
Swipe-Down

# 6. Digital Wallet (from profile)
Write-Host "Digital Wallet..."
Tap 360 370
Take-Shot "customer_06_wallet"
Back

# 7. Order History
Write-Host "Order History..."
Tap 360 510
Take-Shot "customer_07_order_history"
Back

# 8. Address Book
Write-Host "Address Book..."
Tap 360 660
Take-Shot "customer_08_address_book"
Back

# 9. Loyalty Points
Write-Host "Loyalty Points..."
Tap 360 810
Take-Shot "customer_09_loyalty"
Back

# 10. Favorites
Write-Host "Favorites..."
Tap 360 960
Take-Shot "customer_10_favorites"
Back

# 11. Referrals
Write-Host "Referrals..."
Tap 360 1100
Take-Shot "customer_11_referrals"
Back

# 12. Search & Discover
Write-Host "Search & Discover..."
Tap 360 1260
Take-Shot "customer_12_search_discover"
Back

# Scroll down in profile for more items
Swipe-Up
Start-Sleep -Milliseconds 500

# 13. Refund & Dispute
Write-Host "Refund & Dispute..."
Tap 360 370
Take-Shot "customer_13_refund_dispute"
Back

# 14. Group Orders
Write-Host "Group Orders..."
Tap 360 510
Take-Shot "customer_14_group_orders"
Back

# 15. Subscriptions
Write-Host "Subscriptions..."
Tap 360 660
Take-Shot "customer_15_subscriptions"
Back

# 16. Feedback
Write-Host "Feedback..."
Tap 360 810
Take-Shot "customer_16_feedback"
Back

# Now go to Home tab and navigate to a restaurant
Write-Host "Restaurant Detail..."
Tap $navHome[0] $navHome[1]
Start-Sleep -Milliseconds 1500
# Tap on first restaurant card (approximate position)
Swipe-Up
Start-Sleep -Milliseconds 500
Tap 360 600
Take-Shot "customer_17_restaurant_detail"
Back

# Notifications (bell icon on home screen)
Write-Host "Notifications..."
Tap $navHome[0] $navHome[1]
Start-Sleep -Milliseconds 500
Swipe-Down
Start-Sleep -Milliseconds 500
# Notification bell is typically top right
Tap 620 100
Take-Shot "customer_18_notifications"
Back

# Settings
Write-Host "Settings..."
Tap $navProfile[0] $navProfile[1]
Start-Sleep -Milliseconds 500
Swipe-Up
Swipe-Up
# Look for settings/gear at the bottom of profile
Tap 360 1100
Take-Shot "customer_19_settings"
Back

Write-Host ""
Write-Host "=== Auth Screens ==="

# Sign out first to get auth screens
Write-Host "Signing out to capture auth screens..."
Tap $navProfile[0] $navProfile[1]
Start-Sleep -Milliseconds 1000
Swipe-Down
Swipe-Down
Swipe-Down
Start-Sleep -Milliseconds 500
# Scroll to bottom for sign out
Swipe-Up
Swipe-Up
Swipe-Up
Start-Sleep -Milliseconds 500

Write-Host "Done with customer screenshots!"
Write-Host "Screenshots saved to: $screenshotDir"
