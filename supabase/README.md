# Supabase Database Setup - Food Driver App

This directory contains the complete database schema, documentation, and sample data for the Food Driver application.

## 📁 Files Overview

| File | Purpose | Use Case |
|------|---------|----------|
| **complete_schema.sql** | ⭐ Main unified schema file | **Start here** - Contains all 9 tables with indexes and constraints |
| **seed_data.sql** | Sample/test data | Load after schema - Realistic records for development |
| **COLUMNS_DOCUMENTATION.md** | Detailed column reference | Reference guide for developers |
| **migrations/001-009_*.sql** | Individual migration files | Incremental deployment or version control |
| **setup.sh** | Bash automation script | Linux/Mac setup automation |
| **setup.ps1** | PowerShell automation script | Windows setup automation |

## 📊 Database Architecture (9 Tables)

```
users (customers, restaurant owners, drivers, admins)
  ├── restaurants (owned by users)
  │   └── menus (items offered by restaurants)
  ├── drivers (delivery personnel - one per user)
  ├── orders (created by users, filled by restaurants, delivered by drivers)
  │   ├── order_items (dishes in each order)
  │   ├── payments (payment records)
  │   ├── reviews (customer ratings)
  │   └── order_items → menus → restaurants
  └── notifications (alerts sent to users)
```

### Table Columns Summary

| Table | Columns | Key Fields | Purpose |
|-------|---------|-----------|---------|
| **users** | 15 | id, email, role, is_active | Stores all user accounts |
| **restaurants** | 22 | id, owner_id, name, rating, is_verified | Restaurant profiles |
| **menus** | 14 | id, restaurant_id, name, price, category | Food items/dishes |
| **drivers** | 14 | id, user_id, vehicle_type, is_available, documents_status (JSONB) | Delivery drivers |
| **orders** | 24 | id, user_id, restaurant_id, driver_id, status, total_amount | Order tracking |
| **order_items** | 7 | id, order_id, menu_item_id, quantity, price | Line items in orders |
| **payments** | 9 | id, order_id, user_id, amount, status | Payment transactions |
| **reviews** | 8 | id, order_id, user_id, restaurant_id, rating, review_text | Customer feedback |
| **notifications** | 8 | id, user_id, order_id, type, title, body (JSONB) | User notifications |

## 🚀 Quick Start - 3 Ways to Set Up

### ✅ Option 1: Supabase Dashboard (Easiest) - Recommended

1. Open your [Supabase Dashboard](https://app.supabase.io)
2. Go to **SQL Editor** → **New Query**
3. Copy entire contents of **`complete_schema.sql`**
4. Paste into the editor
5. Click **RUN** button
6. ✅ All 9 tables created with indexes and constraints!

To add sample data for testing:
1. Create another **New Query** in SQL Editor
2. Copy entire contents of **`seed_data.sql`**
3. Paste and click **RUN**
4. 📊 Database now has 10+ realistic test records

### ✅ Option 2: Windows PowerShell

```powershell
# Run from this directory
.\setup.ps1
```

This script will:
- Read complete_schema.sql
- Connect to Supabase
- Execute all table creation commands
- Optionally load seed data

### ✅ Option 3: Linux/Mac Bash

```bash
# Make script executable and run
chmod +x setup.sh
./setup.sh
```

This script uses `psql` PostgreSQL client to execute migrations.

## 📚 Complete Column Documentation

See **`COLUMNS_DOCUMENTATION.md`** for:
- Every column with data type and purpose
- Constraints and validation rules
- Foreign key relationships
- Index definitions
- Sample row values
- Query examples

Example structure:
```
users TABLE:
  ├── id (UUID) - Unique user identifier
  ├── email (TEXT NOT NULL UNIQUE) - Authentication email
  ├── name (TEXT) - Full name
  ├── phone (TEXT) - Contact phone
  ├── role (TEXT) - 'user'|'restaurant'|'driver'|'admin'
  ├── address (TEXT) - Physical location
  ├── latitude/longitude (DOUBLE PRECISION) - GPS coordinates
  ├── is_active (BOOLEAN DEFAULT TRUE) - Account status
  ├── created_at (TIMESTAMP) - Signup date
  └── updated_at (TIMESTAMP) - Last updated
  
  Indexes:
    idx_users_email - Fast login lookups
    idx_users_role - Filter by user type
    idx_users_created_at - Analytics/sorting
```

## 📋 Sample Data Details

The **`seed_data.sql`** file creates realistic test data:

### Users (10 records)
- **5 Customers**: Ahmed, Fatima, Mohammed, Rina, Nasir
- **3 Restaurant Owners**: Shahin, Salma, Hassan
- **1 Admin**: System administrator
- **4 Drivers**: Karim, Ravi, Sumon, Tariq (with varied verification status)

### Restaurants (3 records)
- **Spice Kitchen** (Bengali cuisine) - 4.5 stars, verified
- **Taste of Dhaka** (Bangladeshi) - 4.7 stars, verified
- **Global Bites** (International) - 4.3 stars, verified

### Menu Items (15+ dishes)
- Biryani Rice, Tandoori Chicken, Paneer Tikka (Spice Kitchen)
- Hilsa Fry, Chicken Jhol, Mixed Veg Curry (Taste of Dhaka)
- Burger Deluxe, Spaghetti Carbonara, Thai Green Curry (Global Bites)
- Plus beverages and desserts

### Drivers (4 records with different vehicle types)
- Karim Biswas (Bike, 245 deliveries, 4.8 rating, ✅ verified)
- Ravi Sharma (Bike, 189 deliveries, 4.6 rating, ✅ verified)
- Sumon Das (Scooter, 156 deliveries, 4.4 rating, ⏳ pending docs)
- Tariq Khan (Bike, 312 deliveries, 4.9 rating, ✅ verified)

### Orders (5 test orders)
- 3 **delivered** orders with complete payment and 5-star reviews ✅
- 1 **confirmed** order awaiting robot pickup ⏳
- 1 **pending** order just placed 🆕

### Payments & Reviews (3+ complete)
- All delivered orders have payment records
- Customer reviews with ratings from 4.0-5.0 stars
- Realistic transaction IDs and payment methods (card, wallet)

### Notifications (5+ alerts)
- Order status updates (confirmed, ready, delivered)
- Driver assignment notifications
- Driver location updates integrated

## 🔍 Data Relationships & Integrity

The schema enforces data consistency through:

### ✅ Foreign Key Constraints
```
users ← restaurants (via owner_id) [CASCADE DELETE]
users ← drivers (via user_id) [CASCADE DELETE]
users ← orders (via user_id) [CASCADE DELETE]
restaurants ← orders (via restaurant_id) [CASCADE DELETE]
drivers ← orders (via driver_id) [SET NULL on delete]
menus ← order_items (via menu_item_id) [RESTRICT - prevent accidental deletion]
```

### ✅ Data Validation (CHECK Constraints)
```
users.role CHECK (role IN ('user', 'restaurant', 'driver', 'admin'))
orders.status CHECK (status IN ('pending', 'confirmed', 'preparing', 'ready', 'picked_up', 'on_the_way', 'delivered', 'cancelled'))
orders.payment_status CHECK (payment_status IN ('pending', 'completed', 'failed'))
payments.status CHECK (status IN ('pending', 'completed', 'failed'))
reviews.rating CHECK (rating >= 1 AND rating <= 5)
drivers.vehicle_type CHECK (vehicle_type IN ('bike', 'car', 'scooter'))
```

### ✅ Uniqueness Constraints
```
users.email - No duplicate emails
drivers.user_id - One driver profile per user
payments.order_id - One payment per order
reviews.order_id - One review per order
```

## 🗂️ Complex Data Types

### JSONB Fields (Flexible, Queryable)

**drivers.documents_status** (JSONB):
```json
{
  "license": "verified" | "pending" | "rejected",
  "registration": "verified" | "pending" | "rejected",
  "insurance": "verified" | "pending" | "rejected"
}
```

**notifications.data** (JSONB):
```json
{
  "status": "confirmed",
  "order_id": "...",
  "driver_rating": 4.9,
  "priority": "high"
}
```

### Array Fields (TEXT[])

**restaurants.tags** examples:
```
'{"vegan", "fast-delivery", "outdoor-seating"}'
'{"gluten-free", "premium", "new"}'
```

**menus.tags** examples:
```
'{"vegetarian", "spicy", "bestseller"}'
'{"dairy-free", "vegan", "healthy"}'
```

## 📊 Query Examples

### Find Active Drivers Currently Available
```sql
SELECT name, phone, rating, vehicle_type
FROM drivers
JOIN users ON drivers.user_id = users.id
WHERE drivers.is_available = TRUE
  AND drivers.is_verified = TRUE
ORDER BY drivers.rating DESC;
```

### Get Restaurant Menu with Availability
```sql
SELECT resto.name, menu.category, menu.name, menu.price, menu.is_available
FROM menus menu
JOIN restaurants resto ON menu.restaurant_id = resto.id
WHERE resto.name = 'Spice Kitchen'
  AND menu.is_available = TRUE
ORDER BY menu.category, menu.name;
```

### Recent Orders with Customer Reviews
```sql
SELECT 
  orders.id, 
  orders.status,
  users.name as customer,
  restaurants.name as restaurant,
  orders.total_amount,
  reviews.rating,
  reviews.review_text
FROM orders
LEFT JOIN users ON orders.user_id = users.id
LEFT JOIN restaurants ON orders.restaurant_id = restaurants.id
LEFT JOIN reviews ON orders.id = reviews.order_id
WHERE orders.status = 'delivered'
ORDER BY orders.completed_at DESC
LIMIT 10;
```

### Average Delivery Performance
```sql
SELECT 
  drivers.license_number,
  COUNT(orders.id) as total_deliveries,
  AVG(drivers.rating) as avg_rating,
  drivers.vehicle_type
FROM drivers
LEFT JOIN orders ON drivers.id = orders.driver_id
WHERE drivers.is_verified = TRUE
GROUP BY drivers.id
ORDER BY avg_rating DESC;
```

## 🔐 Security Recommendations

After setting up the database, consider:

### 1. Enable Row Level Security (RLS)
```sql
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;
```

### 2. Create RLS Policies (Examples)
```sql
-- Customers can only see their own orders
CREATE POLICY "Users can view their own orders" ON orders
FOR SELECT USING (auth.uid() = user_id);

-- Restaurants can only edit their own profile
CREATE POLICY "Restaurants can edit own profile" ON restaurants
FOR UPDATE USING (auth.uid() = owner_id);
```

### 3. Regular Backups
- Go to Supabase Dashboard → Settings → Backups
- Enable daily backups (included in higher plans)

### 4. Monitor Activity
- Use Supabase Analytics for query performance
- Check database logs for errors

## ⚡ Performance Optimization

The schema includes **38+ optimized indexes** on:
- Foreign key columns (users, restaurants, drivers)
- Frequently filtered fields (status, role, is_verified)
- Time-based queries (created_at, ordered_at)
- Common search patterns (email, cuisine_type)

These ensure queries run in milliseconds even with thousands of records.

## 🐛 Troubleshooting

### Error: "permission denied for schema public"
- Solution: Ensure your Supabase API key has full database access

### Error: "already exists"
- Solution: Key already created - run seed_data.sql to add test data instead

### Foreign Key Violation
- Ensure all referenced IDs exist in parent tables
- Example: Cannot create order without a valid restaurant_id

### Slow Queries
- Check if index exists on WHERE clause columns
- Use `EXPLAIN ANALYZE` to see query plan

## 📞 Support Resources

- **Supabase Docs**: https://supabase.io/docs
- **PostgreSQL Docs**: https://www.postgresql.org/docs/
- **Food Driver App Flutter Code**: See `lib/services/` and `lib/providers/`
- **Model Definitions**: See `lib/models/` for corresponding Dart models

## ✅ Verification Checklist

After setup, verify:

- [ ] All 9 tables created (check Supabase Table Editor)
- [ ] 38+ indexes visible in database inspector
- [ ] Foreign key relationships working
- [ ] Sample data loaded (10+ users, 3 restaurants, 15+ menu items)
- [ ] Queries executing without errors
- [ ] Flutter app can connect and query

## 🎉 Ready to Use!

Your Food Driver app database is now set up and ready for:
- ✅ Development and testing
- ✅ Realtime subscriptions
- ✅ Full auth integration
- ✅ Production deployment

---

**Last Updated**: April 5, 2026  
**Version**: 1.0  
**Status**: Production Ready
2. **restaurants** - Restaurant information and details
3. **menus** - Menu items for each restaurant
4. **drivers** - Driver information and verification status
5. **orders** - Order records
6. **order_items** - Line items for each order
7. **payments** - Payment transaction records
8. **reviews** - Customer reviews and ratings
9. **notifications** - Push notifications

## Important Notes

- All tables use UUID primary keys
- Foreign key constraints are set to CASCADE on delete where appropriate
- Indexes are created for common query patterns
- Timestamps use timezone-aware format (TIMESTAMP WITH TIME ZONE)
- Status fields use CHECK constraints to ensure valid values

## Next Steps

After creating the tables:

1. Enable Row Level Security (RLS) policies on sensitive tables
2. Set up proper database roles and permissions
3. Configure backup policies
4. Create database views for common queries if needed

## Support

For issues with Supabase setup, visit:
- Supabase Documentation: https://supabase.com/docs
- Supabase Community: https://github.com/supabase/supabase
