# pf-stores

Player-owned store system for PF scripts.

## Dependencies
- qb-core
- oxmysql
- pf-computer
- pf-jobs
- pf-trucking

## Status
Implements the first store supply flow (SmoKing):
- pf-computer Order Supplies loads store supply items + stock
- Checkout supports Pickup (instant delivery MVP) or Outsource to Trucking (requires coords)

## Database
Tables are created automatically on resource start via `CREATE TABLE IF NOT EXISTS`.

If you prefer importing manually, run the schema in:
- `install.sql`

### Quick start
1) Ensure `oxmysql` is installed + started.
2) Start `pf-stores`.
3) (Optional) Import `install.sql` if you want to pre-create tables.

### Ownership (access)
Order Supplies for stores is owner-gated.
- Set `pf_stores.owner_citizenid` for `store_id='smoking'`, or
- Temporarily set `Config.DebugAllowAnyOrderSupplies = true` in `shared/config.lua`.
