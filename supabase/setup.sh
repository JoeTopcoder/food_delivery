#!/bin/bash

# Supabase Tables Setup Script
# This script will push all database migrations to Supabase

echo "==================================="
echo "Food Driver - Supabase Setup"
echo "==================================="
echo ""

# Check if SUPABASE_URL and SUPABASE_KEY are set
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_KEY" ]; then
    echo "❌ Error: SUPABASE_URL and SUPABASE_KEY environment variables are not set"
    echo ""
    echo "To set them up:"
    echo "1. Go to your Supabase project dashboard"
    echo "2. Find your project URL and API key"
    echo "3. Set environment variables:"
    echo "   export SUPABASE_URL='your-project-url'"
    echo "   export SUPABASE_KEY='your-api-key'"
    echo ""
    exit 1
fi

echo "✅ Supabase credentials found"
echo ""

# Create a temporary SQL file combining all migrations
TEMP_FILE=$(mktemp)
echo "-- Combined Migration Script for Food Driver App" > "$TEMP_FILE"
echo "-- Generated at $(date)" >> "$TEMP_FILE"
echo "" >> "$TEMP_FILE"

# Cat all migration files in order
for file in supabase/migrations/00*.sql; do
    if [ -f "$file" ]; then
        echo "-- From: $file" >> "$TEMP_FILE"
        cat "$file" >> "$TEMP_FILE"
        echo "" >> "$TEMP_FILE"
    fi
done

echo "Running migrations..."
echo ""

# Execute the combined SQL using psql
psql "postgresql://postgres:[YOUR_PASSWORD]@[YOUR_HOST]/postgres" \
  -U postgres \
  -h "$SUPABASE_HOST" \
  -f "$TEMP_FILE"

# Check if migrations were successful
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ All tables created successfully!"
    echo ""
    echo "Tables created:"
    echo "  • users"
    echo "  • restaurants"
    echo "  • menus"
    echo "  • drivers"
    echo "  • orders"
    echo "  • order_items"
    echo "  • payments"
    echo "  • reviews"
    echo "  • notifications"
    echo ""
else
    echo "❌ Error running migrations"
    exit 1
fi

# Clean up
rm "$TEMP_FILE"

echo "Setup complete! ✨"
