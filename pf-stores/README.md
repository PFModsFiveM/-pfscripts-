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

### Supply orders: what is paid, and when
Stores, restaurants and job businesses order through the same service (`server_orders.lua`, `PFOrders`).
- **Pickup:** the buyer pays the goods, straight to the AI supplier.
- **Delivery:** the buyer pays the goods + the AI markup (`Config.SupplyChain.AIMarkup`) + the trucker's
  freight (the buyer's `trucking.payoutRate`, at least `payoutMin`) on top. All of it is held in the
  `freight_escrow` account until delivery.
- **At delivery:** the driver gets the freight, the supplier the full goods value. An AI supplier also gets
  the markup; a player supplier gets `PlayerSupplierShareOfMarkup` of it and the rest goes back to the buyer.
  Nothing is paid when a player supplier accepts.
- **Cancel** (before a trucker takes it): the buyer gets everything back and reserved supplier stock is
  returned. A refund the bank refuses stays owed and is retried with a new ledger key.
- **Player supplier stock** is counted in cases of `Config.SupplyChain.CaseSize[item]` items (default 1).
