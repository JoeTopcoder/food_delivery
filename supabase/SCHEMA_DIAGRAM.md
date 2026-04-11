# Food Driver Database - Visual Schema Diagram

## 🗺️ Table Relationships Map

```
┌─────────────────────────────────────────────────────────────────┐
│                         DATABASE SCHEMA                          │
└─────────────────────────────────────────────────────────────────┘

                              USERS (Root)
                         ┌───────────┬───────────┬────────────┐
                         │           │           │            │
                     Customer    Restaurant   Driver      Admin
                      (user)       (role)      (role)      (role)
                         │           │           │            
                         │           │           │            
          ┌──────────────┘  ┌────────┴─┐  ┌─────┴──┐         
          │                 │          │  │        │         
      
┌─────────────────┐  ┌──────────────────┐  ┌──────────┐      ┌──────────────┐
│  orders table   │  │ restaurants tbl  │  │ drivers  │      │ menus table  │
│                 │  │                  │  │  table   │      │              │
│ user_id (FK)────┼──→ id (PK)          │  └──┬───────┘      │ restaurant_  │
│ restaurant_id   │  │ owner_id (FK)────┼─────┘              │ id (FK)──────┤
│ driver_id (FK)  │  │ name             │                    │ name         │
│ status          │  │ cuisine_type     │  Each driver:      │ price        │
│ total_amount    │  │ rating           │    - has ONE user  │ category     │
│ payment_status  │  │ delivery_fee     │    - ONE user has  │ is_available │
└────────┬──────────┘  │ is_verified      │      ONE driver    └──────────────┘
         │             │ is_open          │                         ▲
         │             └──────────────────┘                         │
    ┌────┴──────┐                                                   │
    │            │                      ┌──────────────────┐        │
┌───▼────┐   ┌──▼××──────────────┐   ┌──┤ reviews table    │        │
│payments│   │ order_items table │   │  │                 │        │
│ table  │   │                   │   │  │ order_id (FK)   │        │
│        │   │ order_id (FK)─────┼───┤  │ rating (1-5)    │        │
└────────┘   │ menu_item_id(FK)──┼──────┤ review_text     │        │
             │ quantity          │   │  └─────────────────┘        │
             │ price             │   │                              │
             └───────────────────┘   └──────────────────────────────┤
                                                                     │
                                      ┌──────────────────────────────┘
                                      │
                    ┌─────────────────┴──────────────┐
                    │                                │
            ┌───────▼─────────┐         ┌────────────▼────┐
            │notifications tbl│         │ No Direct Link  │
            │                 │         │                 │
            │ user_id (FK)    │         │ menu_items shown│
            │ order_id (FK)   │         │ in order_items  │
            │ title           │         │ via denorm.     │
            │ body            │         └─────────────────┘
            │ is_read         │
            └─────────────────┘
```

---

## 📊 Entity-Relationship Diagram (ERD)

```
USERS (15 cols)
├─ id: UUID (PK)
├─ email: TEXT (UNIQUE)
├─ name, phone: TEXT
├─ role: ENUM (user|restaurant|driver|admin)
├─ address, latitude, longitude: TEXT/DOUBLE
├─ is_active: BOOLEAN
└─ created_at, updated_at: TIMESTAMP

    │
    ├─ ONE-TO-MANY to RESTAURANTS (owner_id) ←─ DELETE CASCADE
    │
    ├─ ONE-TO-ONE to DRIVERS (user_id) ←─ DELETE CASCADE
    │
    ├─ ONE-TO-MANY to ORDERS (user_id) ←─ DELETE CASCADE
    │
    ├─ ONE-TO-MANY to PAYMENTS (user_id) ←─ DELETE CASCADE
    │
    ├─ ONE-TO-MANY to REVIEWS (user_id) ←─ DELETE CASCADE
    │
    └─ ONE-TO-MANY to NOTIFICATIONS (user_id) ←─ DELETE CASCADE


RESTAURANTS (22 cols)
├─ id: UUID (PK)
├─ owner_id: UUID (FK to USERS) ←─ Owner of the restaurant
├─ name, description: TEXT
├─ address, latitude, longitude: TEXT/DOUBLE
├─ cuisine_type, opening_time, closing_time: TEXT
├─ rating, review_count: DOUBLE/INT
├─ delivery_fee, estimated_delivery_time: DOUBLE/INT
├─ is_open, is_verified: BOOLEAN
└─ created_at, updated_at: TIMESTAMP

    │
    ├─ ONE-TO-MANY to MENUS (restaurant_id) ←─ DELETE CASCADE
    │
    ├─ ONE-TO-MANY to ORDERS (restaurant_id) ←─ DELETE CASCADE
    │
    └─ ONE-TO-MANY to REVIEWS (restaurant_id) ←─ DELETE CASCADE


MENUS (14 cols) - Menu Items/Dishes
├─ id: UUID (PK)
├─ restaurant_id: UUID (FK to RESTAURANTS) ←─ DELETE CASCADE
├─ name, description: TEXT
├─ price: DOUBLE PRECISION
├─ category: TEXT (e.g., "Main Course", "Dessert")
├─ is_available, discount: BOOLEAN/DOUBLE
└─ created_at, updated_at: TIMESTAMP

    │
    └─ ONE-TO-MANY to ORDER_ITEMS (menu_item_id) ←─ DELETE RESTRICT


DRIVERS (14 cols)
├─ id: UUID (PK)
├─ user_id: UUID (FK to USERS, UNIQUE) ←─ DELETE CASCADE
├─ vehicle_type: TEXT (bike|car|scooter)
├─ vehicle_number, license_number: TEXT
├─ rating: DOUBLE PRECISION
├─ completed_deliveries: INTEGER
├─ is_available, is_verified: BOOLEAN
├─ current_latitude, current_longitude: DOUBLE (real-time location)
├─ documents_status: JSONB (license, registration, insurance status)
└─ created_at, updated_at: TIMESTAMP

    │
    └─ ONE-TO-MANY to ORDERS (driver_id) ←─ DELETE SET NULL


ORDERS (24 cols) - The Main Table
├─ id: UUID (PK)
├─ user_id: UUID (FK to USERS) ←─ DELETE CASCADE (customer)
├─ restaurant_id: UUID (FK to RESTAURANTS) ←─ DELETE CASCADE
├─ driver_id: UUID (FK to DRIVERS, NULLABLE) ←─ DELETE SET NULL
├─ subtotal, tax_amount, delivery_fee, discount, total_amount: DOUBLE
├─ status: ENUM (pending|confirmed|preparing|ready|picked_up|on_the_way|delivered|cancelled)
├─ payment_status: ENUM (pending|completed|failed)
├─ delivery_address, notes: TEXT
├─ delivery_latitude, delivery_longitude: DOUBLE
├─ payment_method: TEXT
├─ ordered_at, confirmed_at, completed_at, cancelled_at: TIMESTAMP
├─ user_rating, user_review: DOUBLE/TEXT (after delivery)
└─ created_at, updated_at: TIMESTAMP

    │
    ├─ ONE-TO-MANY to ORDER_ITEMS ←─ DELETE CASCADE
    │
    ├─ ONE-TO-ONE to PAYMENTS ←─ DELETE CASCADE, UNIQUE
    │
    ├─ ONE-TO-ONE to REVIEWS ←─ DELETE CASCADE, UNIQUE
    │
    └─ ONE-TO-MANY to NOTIFICATIONS (order_id) ←─ DELETE CASCADE


ORDER_ITEMS (7 cols) - Line Items
├─ id: UUID (PK)
├─ order_id: UUID (FK to ORDERS) ←─ DELETE CASCADE
├─ menu_item_id: UUID (FK to MENUS) ←─ DELETE RESTRICT
├─ item_name, notes: TEXT (denormalized snap)
├─ price, quantity: DOUBLE/INTEGER
└─ created_at: TIMESTAMP


PAYMENTS (9 cols)
├─ id: UUID (PK)
├─ order_id: UUID (FK to ORDERS, UNIQUE) ←─ DELETE CASCADE
├─ user_id: UUID (FK to USERS) ←─ DELETE CASCADE
├─ amount: DOUBLE PRECISION
├─ method: TEXT (card|wallet|cash)
├─ status: ENUM (pending|completed|failed)
├─ transaction_id, error_message: TEXT
└─ created_at, updated_at: TIMESTAMP


REVIEWS (8 cols)
├─ id: UUID (PK)
├─ order_id: UUID (FK to ORDERS, UNIQUE) ←─ DELETE CASCADE
├─ user_id: UUID (FK to USERS) ←─ DELETE CASCADE
├─ restaurant_id: UUID (FK to RESTAURANTS) ←─ DELETE CASCADE
├─ rating: DOUBLE PRECISION (CHECK 1-5)
├─ review_text: TEXT
└─ created_at, updated_at: TIMESTAMP


NOTIFICATIONS (8 cols)
├─ id: UUID (PK)
├─ user_id: UUID (FK to USERS) ←─ DELETE CASCADE
├─ order_id: UUID (FK to ORDERS, NULLABLE) ←─ DELETE CASCADE
├─ type: TEXT (order_status|delivery_assigned|payment|etc)
├─ title, body: TEXT
├─ data: JSONB (flexible notification data)
├─ is_read: BOOLEAN
└─ created_at: TIMESTAMP
```

---

## 🔄 Data Flow Diagrams

### Order Creation Flow
```
Customer (USER)
    ↓
    └─→ Creates ORDER
        ├─ user_id = customer ID
        ├─ restaurant_id = selected restaurant
        ├─ status = 'pending'
        └─ payment_status = 'pending'
            ↓
            └─→ Adds ORDER_ITEMS (dishe selected)
                ├─ menu_item_id → MENUS table
                ├─ quantity from customer
                └─ price denormalized
                    ↓
                    └─→ Creates PAYMENT record
                        ├─ amount = total_amount
                        ├─ method = customer's choice
                        └─ status = 'pending'
                            ↓
                            └─→ Sends NOTIFICATION
                                ├─ type = 'order_confirmed'
                                ├─ user_id = customer
                                └─ order_id = order ID
```

### Order Delivery Flow
```
Restaurant
    ↓
    └─→ Updates ORDER status
        ├─ 'pending' → 'confirmed'
        ├─ 'confirmed' → 'preparing'
        ├─ 'preparing' → 'ready'
            ↓
            └─→ Driver Assignment System
                ├─ Finds available DRIVER
                ├─ Updates order.driver_id
                ├─ Updates order.status = 'picked_up'
                └─ Sends NOTIFICATION to driver
                    ↓
                    └─→ Driver Real-time Updates
                        ├─ Updates driver.current_latitude/longitude
                        ├─ Updates order.status = 'on_the_way'
                        ├─ Sends location NOTIFICATION to customer
                            ↓
                            └─→ Delivery Complete
                                ├─ Updates order.status = 'delivered'
                                ├─ Updates order.completed_at
                                ├─ Updates order.payment_status = 'completed'
                                ├─ Creates REVIEW record (if customer adds)
                                └─ Sends NOTIFICATION (delivered confirmation)
```

---

## 🔑 Key Relationships

### Many-to-One (FK with CASCADE)
- **RESTAURANTS** → USERS (many restaurants, one owner)
- **ORDERS** → USERS (many orders, one customer)
- **ORDERS** → RESTAURANTS (many orders, one restaurant)
- **MENUS** → RESTAURANTS (many items, one restaurant)
- **ORDER_ITEMS** → ORDERS (many items, one order)
- **ORDER_ITEMS** → MENUS (many orders, one menu item)
- **PAYMENTS** → USERS (many payments, one customer)
- **PAYMENTS** → ORDERS (one-to-one, unique)
- **REVIEWS** → USERS (many reviews, one customer)
- **REVIEWS** → RESTAURANTS (many reviews, one restaurant)
- **NOTIFICATIONS** → USERS (many notifications, one recipient)
- **NOTIFICATIONS** → ORDERS (many notifications, one order)

### One-to-One (FK, UNIQUE)
- **DRIVERS** ↔ USERS (one driver per user, one user can be one driver)
- **PAYMENTS** ↔ ORDERS (one payment per order)
- **REVIEWS** ↔ ORDERS (one review per order)

### Nullable FKs (Reference but not mandatory)
- **ORDERS.driver_id** - NULL until assigned (SET NULL on driver delete)
- **NOTIFICATIONS.order_id** - NULL for system-wide notifications

---

## 📈 Data Scale Example

For 1 Million Users:

```
users:                 1,000,000 rows
restaurants:             10,000 rows (10 per city)
menus:                  100,000 rows (10 items per restaurant)
drivers:                 50,000 rows (5% are drivers)
orders:               10,000,000 rows (10 per user average)
order_items:          30,000,000 rows (3 items per order)
payments:             10,000,000 rows (1:1 with orders)
reviews:               5,000,000 rows (50% of delivered orders)
notifications:        50,000,000 rows (5 per order)
                      ────────────────────
Total:               106,160,000 rows
Index storage:        ~40-50 GB
Raw data storage:     ~80-100 GB
```

With proper indexes, query response time stays < 100ms.

---

## 🎯 Query Optimization Points

### Indexed Columns for Fast Queries
```
Users:              email, role, created_at
Restaurants:        owner_id, is_verified, cuisine_type, is_open
Menus:              restaurant_id, category, is_available
Drivers:            user_id, is_verified, is_available
Orders:             user_id, restaurant_id, driver_id, status, payment_status, ordered_at
Reviews:            user_id, restaurant_id, rating
Payments:           user_id, status, created_at
Notifications:      user_id, is_read, created_at
```

### Example Query Paths
```
Find restaurants by cuisine:
  restaurants.cuisine_type → idx_restaurants_cuisine_type (FAST ✓)

Find driver's completed deliveries:
  orders.driver_id → idx_orders_driver_id (FAST ✓)
  
Find pending payments:
  payments.status → idx_payments_status (FAST ✓)

Get 5-star reviews:
  reviews.rating → idx_reviews_rating
  THEN filter rating = 5 (FAST ✓)
```

---

**Last Updated**: April 5, 2026
