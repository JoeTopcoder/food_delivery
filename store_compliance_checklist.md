# 7Dash — Store Compliance Checklist
**App:** 7Dash (SevenDash Technologies Limited)  
**Prepared:** June 2026  
**Target stores:** Apple App Store, Google Play Store

---

## Part 1 — Data Safety (Google Play Data Safety Form)

| Data Category | Data Point | Collected | Purpose | Shared w/ 3rd Party | Encrypted in Transit | User Can Delete |
|---|---|---|---|---|---|---|
| Personal info | Full name | Yes | Account, orders | No | Yes (TLS) | Yes |
| Personal info | Email address | Yes | Auth, communications | No | Yes | Yes |
| Personal info | Phone number | Yes | Orders, delivery | No | Yes | Yes |
| Personal info | Profile photo | Optional | Account display | No | Yes | Yes |
| Personal info | Password | Yes (hashed) | Auth (Supabase) | No | Yes | Yes |
| Financial info | Payment instrument (token) | Yes | Payments | Yes (Stripe) | Yes | Yes |
| Financial info | Purchase history | Yes | Order management | No | Yes | Yes |
| Location | Precise location | Yes (drivers + customers) | Delivery, ride matching | No | Yes | Yes |
| Location | Approximate location | No | — | — | — | — |
| Messages | In-app messages | Yes | Customer-driver comms | No | Yes | Yes |
| Photos/videos | Photos | Optional | Profile, proof of delivery | No | Yes | Yes |
| Audio | Voice call audio | If call made | Driver-customer calls (Agora) | Yes (Agora) | Yes | N/A |
| App activity | App interactions | Yes | Analytics, recommendations | No | Yes | Yes |
| App info | Crash logs | Yes | Bug fixing | No | Yes | N/A |
| Device IDs | Notification token | Yes | Push notifications | No | Yes | Yes |
| Device IDs | IP address | Yes | Security, fraud prevention | No | Yes | N/A |

### Data Safety Notes
- Data is collected only for purposes listed above.
- Payment card data is handled entirely by Stripe; we do not store card numbers, CVV, or track 1/2 data.
- Precise location is only collected while the app is in use (or while a driver is on an active trip, if background location permission was granted).
- All data is transmitted over TLS 1.2+.
- Users can delete their account via Settings → Delete Account or via the Data Deletion Request form.

---

## Part 2 — Apple App Store Privacy Nutrition Labels

### Data Linked to User
| Data Type | Use |
|---|---|
| Name | Account, order display |
| Email | Auth, notifications |
| Phone number | Delivery, support |
| Payment info | Purchases via Stripe |
| Purchase history | Order management |
| Precise location | Delivery/ride matching |
| Photos | Profile, delivery proof |
| Customer support data | Support requests |
| Product interaction | Personalization |
| Crash data | App stability |
| Device ID | Push notifications |

### Data Not Linked to User
| Data Type | Use |
|---|---|
| Coarse location (anonymized) | Aggregate analytics |

### Data Not Collected
- Browsing history
- Search history (external)
- Health & fitness
- Sensitive info
- Contacts

---

## Part 3 — Required Compliance Screens (Implementation Status)

| Screen | Route | Public Access | Status |
|---|---|---|---|
| Privacy Policy | `/privacy-policy` | Yes | ✅ Implemented |
| Terms & Conditions | `/terms` | Yes | ✅ Implemented |
| Refund Policy | `/refund-policy` | Yes | ✅ Implemented |
| Cancellation Policy | `/cancellation-policy` | Yes | ✅ Implemented |
| Driver Safety Policy | `/driver-safety-policy` | Yes | ✅ Implemented |
| Restaurant/Provider Terms | `/provider-terms` | Yes | ✅ Implemented |
| Subscription Terms | `/subscription-terms` | Yes | ✅ Implemented |
| About App | `/about` | Yes | ✅ Implemented |
| Legal Center | `/legal` | Yes | ✅ Implemented |
| Delete Account (in-app) | `/delete-account` | Auth required | ✅ Implemented |
| Data Deletion Request | `/data-deletion-request` | Yes | ✅ Implemented |
| Contact Support | `/contact-support` | Yes | ✅ Implemented |
| Location Permission | `/permissions/location` | N/A | ✅ Implemented |
| Camera Permission | `/permissions/camera` | N/A | ✅ Implemented |
| Microphone Permission | `/permissions/microphone` | N/A | ✅ Implemented |
| Notification Permission | `/permissions/notifications` | N/A | ✅ Implemented |
| Report User | `/report-user` | Auth required | ✅ Implemented |

---

## Part 4 — Backend Compliance (Supabase)

| Table | Purpose | RLS | Status |
|---|---|---|---|
| `support_requests` | Customer support form submissions | Users insert own; admin reads/updates all | ✅ Migration created |
| `user_deletion_requests` | Account/data deletion requests | Public insert; admin reads/updates | ✅ Migration created |
| `chat_reports` | User and message reports | Auth insert; admin reads/updates | ✅ Migration created |

---

## Part 5 — Permission Disclosures

| Permission | When Requested | Explanation Screen | Graceful Denial |
|---|---|---|---|
| Location (when in use) | When customer enters delivery flow or driver goes online | `/permissions/location` | Yes — app continues without delivery tracking |
| Camera | When user taps photo upload | `/permissions/camera` | Yes — upload skipped |
| Microphone | When user initiates a call | `/permissions/microphone` | Yes — call feature unavailable |
| Notifications | After account creation | `/permissions/notifications` | Yes — in-app updates still work |

---

## Part 6 — Reviewer Demo Access

**Email:** `reviewer@7dash.app`  
**Password:** `Review123!`  
**Role:** Customer  

**Setup instructions (Supabase Dashboard):**
1. Go to Authentication → Users → Invite User
2. Enter `reviewer@7dash.app`
3. In the `users` table, set `role = 'customer'` for this user
4. Manually confirm the email in Auth dashboard so no OTP is required
5. Test login with above credentials before submitting for review

**What reviewer can do:**
- Browse restaurants and menus
- Add items to cart
- Reach checkout (Stripe test mode active)
- View all legal screens
- Open settings, delete account screen
- View order history (empty is fine)
- Access profile and notifications

---

## Part 7 — Apple App Review Notes Template

```
REVIEWER NOTES — 7Dash

Demo Account:
Email: reviewer@7dash.app
Password: Review123!

This account has been pre-configured for review. No OTP or phone 
verification is required.

Permissions:
- Location: used for delivery address and real-time order tracking
- Camera: used for profile photo and order issue photos
- Microphone: used for optional in-app voice calls (Agora)
- Notifications: used for order status updates and driver alerts

Payment:
- Stripe is in test mode for the reviewer account. Use test card 
  4242 4242 4242 4242 (any future expiry, any CVV) to complete checkout.

Notes:
- The app requires an internet connection to load restaurant data.
- Empty states are shown when no data is available.
- All legal documents are accessible from Settings → Legal Center 
  without requiring login.
- Account deletion is available at Settings → Delete Account.
```

---

## Part 8 — Google Play Review Notes Template

```
TESTING INSTRUCTIONS — 7Dash

Login Credentials:
Email: reviewer@7dash.app
Password: Review123!

The reviewer account has customer role access. No OTP is required.

Key Flows to Test:
1. Login → Browse restaurants → Add to cart → Checkout
2. Settings → Legal Center (Privacy, Terms, etc.)
3. Settings → Delete Account
4. Profile → Contact Support
5. Any screen → Back navigation works correctly

Data Deletion URL:
The in-app data deletion flow is at Settings → Delete Account.
The public form is accessible at Settings → Legal Center → Data Deletion Request.

Permissions:
All permissions are optional for basic browsing. The app does not crash 
if permissions are denied. Explanatory screens are shown before any 
OS permission dialog is triggered.
```

---

## Part 9 — Pre-Submission Checklist

### Build
- [ ] Debug banner disabled (`debugShowCheckedModeBanner: false` in MaterialApp)
- [ ] No `print()` statements in production (use AppLogger)
- [ ] No hardcoded localhost URLs
- [ ] No Supabase service role key in Flutter client code
- [ ] Stripe publishable key (not secret key) used in client
- [ ] App version / build number incremented

### UI / UX
- [ ] No RenderFlex overflow errors on test devices
- [ ] All screens scroll on small devices (375pt width)
- [ ] Empty states on: Home, Restaurant list, Cart, Orders, Notifications
- [ ] Loading states on all async operations
- [ ] Error states on all async operations
- [ ] No placeholder "Lorem ipsum" text
- [ ] No dead (no-op) buttons

### Auth
- [ ] Reviewer account logs in without OTP
- [ ] Sign-out works and clears state
- [ ] Delete account flow completes and signs user out

### Permissions
- [ ] Denying location does not crash
- [ ] Denying camera does not crash
- [ ] Denying notifications does not crash
- [ ] Permanently denied shows "Open Settings" option

### Legal
- [ ] Privacy Policy accessible without login
- [ ] Terms accessible without login
- [ ] Data Deletion Request accessible without login
- [ ] Legal Center lists all documents
- [ ] All legal screens scroll on small phones
- [ ] Legal Center reachable from Settings and Profile

### Backend
- [ ] `support_requests` table exists with correct RLS
- [ ] `user_deletion_requests` table exists with correct RLS
- [ ] `chat_reports` table exists with correct RLS
- [ ] Reviewer account created in Supabase Auth dashboard
- [ ] Reviewer account email confirmed manually

### Store Forms
- [ ] Google Play Data Safety form completed
- [ ] Apple Privacy Nutrition Labels completed
- [ ] Account deletion URL submitted to Google Play
- [ ] Privacy Policy URL submitted to both stores
- [ ] Support email on store listing: support@7dash.app

---

## Part 10 — Contact & Legal Config (Update Before Submission)

Update these values in `lib/config/app_constants.dart` before submitting:

| Constant | Current Value | Action Required |
|---|---|---|
| `supportPhoneDisplay` | `TODO_CONFIGURE` | Add real phone number |
| `supportWhatsAppDisplay` | `TODO_CONFIGURE` | Add WhatsApp number or remove |
| `businessAddress` | `TODO_CONFIGURE` | Add registered business address |
| `appBaseUrl` | `https://mealhubcayman.com` | Update to `https://7dash.app` or current domain |

---

*Generated by Claude Code — update this document before each store submission.*
