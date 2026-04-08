---
paths:
  - "db/**"
---

# Database Migrations — MUST BE BACKWARDS COMPATIBLE

**CRITICAL**: Migrations run BEFORE new code deploys. This means:
1. Migration runs on database
2. Old code briefly runs with new schema
3. New code starts

## Safe Migration Patterns

```ruby
# Adding columns (with or without defaults)
add_column :products, :new_field, :string
add_column :products, :status, :integer, default: 0

# Relaxing constraints (NOT NULL → nullable)
change_column_null :products, :url, true

# Adding indexes
add_index :products, :new_field

# Adding new tables
create_table :new_things do |t|
  # ...
end
```

## Dangerous Migration Patterns

```ruby
remove_column :products, :old_field                          # Old code may still reference!
rename_column :products, :old_name, :new_name                # Old code uses old name!
add_column :products, :required_field, :string, null: false  # Existing rows fail!
change_column :products, :count, :string                     # May lose data!
```

## Safe Column Removal (2-step)

1. **Release 1**: Deploy code that stops using the column
2. **Release 2**: Remove the column in migration

## Safe Column Rename (3-step)

1. **Release 1**: Add new column, write to both old and new
2. **Release 2**: Migrate data, read from new, stop writing to old
3. **Release 3**: Remove old column
