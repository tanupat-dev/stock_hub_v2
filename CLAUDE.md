# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commit Checklist

Before every commit:
1. Run `bin/rails test` — fix all failures before committing.
2. Run `bundle exec rubocop` — fix all offenses before committing.

## Commands

```bash
# Server
./bin/rails server              # Dev server
./bin/jobs                      # Start SolidQueue worker (required for background jobs)

# Database
./bin/rails db:create db:migrate
./bin/rails db:migrate          # Run pending migrations
./bin/rails db:rollback         # Roll back last migration

# Tests
./bin/rails test                # Run full Minitest suite
./bin/rails test test/models/sku_test.rb        # Run a specific test file
./bin/rails test test/models/sku_test.rb:42     # Run a specific test by line number
bundle exec rspec               # Run RSpec suite (BDD-style tests)

# Code Quality
bundle exec brakeman            # Security audit
bundle exec rubocop             # Linting

# Console
./bin/rails console
```

## Architecture

This is a **multi-channel inventory and POS management system** for retail/e-commerce. It aggregates stock across a physical POS and online marketplaces (TikTok Shop, Lazada, Shopee), maintaining a single source of truth for inventory.

### Core Domain Model

```
Shop (channel: tiktok | lazada | shopee | pos)
  └── SkuMappings → Sku (global catalog unit)
                      └── InventoryBalance (on_hand, reserved, available)
                      └── StockMovements (audit trail)

Order (from marketplace polling)
  └── OrderLines
ReturnShipment (inbound customer returns)
  └── ReturnShipmentLines
PosSale (in-store transaction)
  └── PosSaleLines
```

**StockIdentity** groups multiple SKUs that share physical stock (e.g., a product sold in the same colorway under different barcodes). `InventoryBalance` is the authoritative source; `on_hand - reserved = available` is enforced at the application layer with database locking.

### Service Layer

All complex business logic lives in `app/services/`, namespaced by domain. Services expose a single `.call!` class method:

```ruby
Inventory::Adjust.call!(sku: sku, delta: qty, idempotency_key: key)
Pos::Checkout.call!(sale: sale, idempotency_key: key)
Marketplace::TikTok::PushInventory.call!(shop: shop, sku: sku)
```

Key namespaces:
- `Inventory::` — stock adjustments, oversell detection, freeze logic, stock sync
- `Pos::` — cart lifecycle (create → add lines → checkout), retail returns, stock counts
- `Marketplace::TikTok::`, `Marketplace::Lazada::`, `Marketplace::Shopee::` — catalog sync, order polling, return imports
- `Orders::` — cross-channel order aggregation and return tracking

### Idempotency

All transactional operations require an `idempotency_key` parameter. Before executing, services check `InventoryAction.exists?(idempotency_key:)` (or similar). This is critical for safety in async and retry contexts — never skip it.

### Background Jobs & Scheduling

Uses **SolidQueue** (not Sidekiq). Jobs are in `app/jobs/`. Recurring schedules are defined in `config/recurring.yml` with environment-specific entries (development and production differ). The worker process must run separately (`./bin/jobs`).

Key recurring patterns:
- Marketplace order polling → syncs new orders/returns
- `StockSync::RequestDebouncer` → batches inventory push to marketplaces
- Oversell detection and freeze jobs

### Stock Sync Flow

When an `InventoryBalance` changes, an `after_commit` hook enqueues a debounced sync request. `PushInventoryJob` then calls the relevant marketplace API. A rollout system (`StockSyncRollout`) controls which SKU/shop combinations are live.

### Stock Protection

Two mechanisms prevent overselling:
1. **Freeze** — `InventoryBalance#frozen_at` prevents allocation when set. Set automatically on detected discrepancy.
2. **Buffer quantity** — `Sku#buffer_quantity` reduces available stock exposed to online marketplaces (safety stock). Enforced by a DB check constraint (`>= 0`).

### Shopee Integration

Shopee does not have a polling API like TikTok/Lazada. Instead, order/return data is imported via Excel files (`.xlsx` or `.xls`) uploaded through `app/controllers/shopee/`. The `roo`/`roo-xls` gems handle parsing.

### Routes Structure

```
/ops/...       # Admin/operations UI (Hotwire-driven)
/pos/...       # POS API endpoints (JSON)
/shopee/...    # Shopee import webhooks/uploads
/oauth/...     # TikTok & Lazada OAuth2 flows
```

### Frontend

Uses Hotwire (Turbo + Stimulus) with Importmap — no webpack/bundler. Assets served via Propshaft. No React or Vue.

### Deployment

Hetzner VPS at `5.223.56.196` (Singapore). Three Docker Compose containers: `web` (Puma + Thruster), `worker` (SolidQueue), `db` (PostgreSQL). Domain `thailumlong.in.th` served via Nginx + SSL on the host.

CI/CD: GitHub Actions builds the Docker image, pushes to `ghcr.io/tanupat-dev/stock_hub_v2:latest`, then deploys via SSH — pulls the new image and restarts `web` and `worker` with `docker compose up -d --no-deps`.

Multi-database setup: separate PostgreSQL databases for primary, cache (SolidCache), queue (SolidQueue), and cable (SolidCable) in production.
