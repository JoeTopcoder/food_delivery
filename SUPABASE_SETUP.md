# Supabase Database Setup - Quick Start Guide

Complete database setup in **5 minutes or less**!

Complete documentation: [`supabase/README.md`](supabase/README.md)

---

## ⚡ Method 1: Supabase Dashboard (Easiest) ⭐

### Step 1: Open Supabase SQL Editor
1. Go to [app.supabase.com](https://app.supabase.com)
2. Select your project
3. Click **SQL Editor** → **New query**

### Step 2: Create Tables
1. Open the file: [`supabase/complete_schema.sql`](supabase/complete_schema.sql)
2. **Copy** the entire file content
3. **Paste** into the SQL Editor in Supabase
4. Click **RUN** button

✅ **All 9 tables created!** (You'll see this in Supabase Table Editor)

### Step 3 (Optional): Add Sample Data
For testing with realistic data:

1. Create a **New query** in SQL Editor
2. Open: [`supabase/seed_data.sql`](supabase/seed_data.sql)
3. **Copy** and **Paste** into the editor
4. Click **RUN**

✅ **10+ test users, 3 restaurants, 15+ menu items, sample orders**

---

## 🔧 Method 2: Windows PowerShell

```powershell
cd C:\Users\scott\Documents\Bank\food_driver

# Run the setup script
.\supabase\setup.ps1
```

The script will prompt for your Supabase credentials and execute all SQL.

---

## 🔧 Method 3: Linux/Mac Bash

```bash
cd ~/Documents/Bank/food_driver

# Make executable and run
chmod +x supabase/setup.sh
./supabase/setup.sh
```

Requires `psql` PostgreSQL client (install via Homebrew or apt).

---

## 📊 What Gets Created

**9 Database Tables** with **38+ optimized indexes**:

| Table | Columns | Purpose |
|-------|---------|---------|
| **users** | 15 | Customers, restaurants, drivers, admins |
| **restaurants** | 22 | Restaurant profiles, hours, ratings |
| **menus** | 14 | Food items/dishes offered |
| **drivers** | 14 | Delivery personnel, vehicle info |
| **orders** | 24 | Order tracking with status |
| **order_items** | 7 | Individual dishes in each order |
| **payments** | 9 | Payment transactions |
| **reviews** | 8 | Customer ratings and feedback |
| **notifications** | 8 | In-app notifications |

---

## 📁 File Reference

| File | What It Does |
|------|-------------|
| `supabase/complete_schema.sql` | ⭐ **Main file** - All 9 tables, constraints, indexes |
| `supabase/seed_data.sql` | Sample data - 10+ realistic test records |
| `supabase/README.md` | **Full documentation** - Detailed schema info, queries, security |
| `supabase/COLUMNS_DOCUMENTATION.md` | Column-by-column reference guide |
| `supabase/migrations/001-009_*.sql` | Individual table files (if incremental deploy needed) |
| `supabase/setup.sh` | Bash automation (Linux/Mac) |
| `supabase/setup.ps1` | PowerShell automation (Windows) |

---

## 🔍 Verify Your Setup

After setup, check Supabase Dashboard:

1. **Table Editor** → Should show 9 tables ✅
2. **SQL Editor** → Try this query:
   ```sql
   ```sql
   SELECT table_name 
   FROM information_schema.tables 
   WHERE table_schema = 'public'
   ORDER BY table_name;
   ```
   Should return: users, restaurants, menus, drivers, orders, order_items, payments, reviews, notifications

3. **View Sample Data**:
   ```sql
   SELECT name, role FROM public.users LIMIT 5;
   SELECT name, cuisine_type FROM public.restaurants;
   SELECT COUNT(*) as total_menu_items FROM public.menus;
   ```

---

## 📚 Schema Overview

```
Database Structure:
├── users (10 sample records)
│   ├── 5 customers
│   ├── 3 restaurant owners
│   ├── 4 drivers
│   └── 1 admin
│
├── restaurants (3 sample: Spice Kitchen, Taste of Dhaka, Global Bites)
│   └── menus (5 items per restaurant = 15 total)
│
├── drivers (4 sample)
│   └── linked to users (one-to-one)
│
├── orders (5 sample: 3 delivered, 1 confirmed, 1 pending)
│   ├── order_items (dishes in each order)
│   ├── payments (payment records)
│   ├── reviews (customers' ratings)
│   └── notifications (status updates)
```

---

## ⚙️ Column Data Types Used

- **UUID** - 36-character unique IDs (e.g., `123e4567-e89b-12d3-a456-426614174000`)
- **TEXT** - Variable text strings
- **DOUBLE PRECISION** - Decimal numbers (prices, ratings, coordinates)
- **INTEGER** - Whole numbers (quantities, counts)
- **BOOLEAN** - TRUE/FALSE flags
- **TIMESTAMP WITH TIME ZONE** - Dates with timezone
- **TEXT[]** - Arrays of text (tags, categories)
- **JSONB** - Flexible JSON data (driver documents, notification data)

See `supabase/COLUMNS_DOCUMENTATION.md` for complete reference.

---

## 🔐 Next Steps: Security Setup (Optional)

After tables are created, you may want to:

1. **Enable Row Level Security (RLS)** - Control who sees what data
2. **Set up Backups** - Automatic daily backups
3. **Add RLS Policies** - Enforce data access rules

See `supabase/README.md` for detailed security setup.

---

## 💡 Common Queries

Once set up, you can use these queries:

### Get All Restaurants
```sql
SELECT name, cuisine_type, rating, is_open 
FROM restaurants 
ORDER BY rating DESC;
```

### Find Available Drivers
```sql
SELECT users.name, drivers.vehicle_type, drivers.rating
FROM drivers
JOIN users ON drivers.user_id = users.id
WHERE drivers.is_available = TRUE;
```

### View Recent Orders
```sql
SELECT orders.id, users.name as customer, restaurants.name, orders.status
FROM orders
JOIN users ON orders.user_id = users.id
JOIN restaurants ON orders.restaurant_id = restaurants.id
ORDER BY orders.ordered_at DESC LIMIT 10;
```

### Average Order Value
```sql
SELECT AVG(total_amount) as avg_order_value, COUNT(*) as total_orders
FROM orders WHERE status = 'delivered';
```

---

## ✅ Checklist - You're Done When:

- [ ] SQL file pasted into Supabase SQL Editor
- [ ] **RUN** button clicked successfully
- [ ] No errors shown ✅
- [ ] Supabase Table Editor shows 9 tables
- [ ] Can see users, restaurants, and other tables
- [ ] (Optional) Seed data loaded with sample records
- [ ] (Optional) Ran verification queries above successfully

---

## 🎉 Success!

Your Food Driver app database is ready!

**Next**: Update your Flutter app's `.env` file or Supabase config with:
- Project URL
- Anon Key
- Database URL

Then run: `flutter pub get && flutter run`

---

## 📖 Need More Help?

- **Full Schema Documentation**: [`supabase/README.md`](supabase/README.md)
- **Column Reference**: [`supabase/COLUMNS_DOCUMENTATION.md`](supabase/COLUMNS_DOCUMENTATION.md)
- **Supabase Docs**: https://supabase.io/docs
- **Flutter Supabase**: https://supabase.io/docs/reference/flutter

---

**Ready to go!** 🚀
```powershell
cd .\supabase
.\setup.ps1
```

### Method 4: Individual Migration Files
Run each file separately in order:
1. `001_create_users_table.sql`
2. `002_create_restaurants_table.sql`
3. `003_create_menus_table.sql`
4. `004_create_drivers_table.sql`
5. `005_create_orders_table.sql`
6. `006_create_order_items_table.sql`
7. `007_create_payments_table.sql`
8. `008_create_reviews_table.sql`
9. `009_create_notifications_table.sql`

---

## ✅ Verify Tables Were Created

After running the SQL, verify in your Supabase dashboard:

1. Go to **Table Editor**
2. You should see all 9 tables listed
3. Click each table to verify columns

---

## 🔐 Next Steps (Recommended)

### 1. Enable Row Level Security
```sql
-- In Supabase SQL Editor, run:
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
-- ... and so on for other tables
```

### 2. Create Policies
Set up RLS policies to control data access based on user roles.

### 3. Enable Backups
In Supabase Settings → Backups, ensure automatic backups are enabled.

---

## 📝 File Structure

```
supabase/
├── complete_schema.sql           # ← USE THIS (all tables in one file)
├── setup.sh                       # Setup script for Linux/Mac
├── setup.ps1                      # Setup script for Windows
├── README.md                      # Detailed documentation
└── migrations/                    # Individual SQL files
    ├── 001_create_users_table.sql
    ├── 002_create_restaurants_table.sql
    ├── 003_create_menus_table.sql
    ├── 004_create_drivers_table.sql
    ├── 005_create_orders_table.sql
    ├── 006_create_order_items_table.sql
    ├── 007_create_payments_table.sql
    ├── 008_create_reviews_table.sql
    └── 009_create_notifications_table.sql
```

---

## 🐛 Troubleshooting

**Error: Table already exists**
- Drop existing tables first, or modify CREATE TABLE to CREATE TABLE IF NOT EXISTS

**Error: Foreign key constraint**
- Ensure you create parent tables before child tables
- The SQL is already ordered correctly

**Error: Supabase connection refused**
- Check your project URL and API key
- Ensure your Supabase project is active

---

## 📞 Support

- **Supabase Docs**: https://supabase.com/docs
- **Database Schema**: See `PHASE_6_DOCUMENTATION.md` in project root
- **Flutter App Issues**: Check `README.md` in project root

---

**Setup Complete!** Your Supabase database is now ready for the Food Driver app. 🚀
