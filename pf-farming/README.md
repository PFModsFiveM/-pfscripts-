# pf-farming

Crop farming on top of the shared PF systems. It has no economy of its own:
- crops are ordinary pfm-inventory items with freshness (category `produce`);
- money goes through the pfm-banking ledger;
- sales to businesses go through pf-stores' player suppliers.

## Playing
- **Get seeds:** buy them at the produce market with `/buyseeds <crop> <amount>`. The crops are tomato, lettuce, potato, onion, bell_pepper and garlic.
- **Plant:** stand in a field and use `/plant <crop>`. The plot goes where you stand, and planting waters it once.
- **Water:** press **E** at your plot. One watering uses one `water_bottle` and lasts the crop's `waterMinutes`.
- **Grow:** a crop grows only while watered, and keeps growing while you are offline.
  - A plot left dry for `DieAfterDryMinutes` dies.
  - A ripe crop left for `RotAfterReadyMinutes` rots.
- **Harvest:** press **E** on a ripe plot. **G** clears a plot.
- **Sell to the market:** `/sellproduce <item> <amount>`. The market pays less for stale produce and refuses spoiled produce.
- **Sell to businesses (pays better):**
  1. `/supplier <name>` registers you as a supplier.
  2. `/supplyoffer tomato <price>` sets your price, capped at the AI wholesale price.
  3. `/supplystock tomato <cases>` stocks your offer from your inventory.
  4. Orders from restaurants and stores come to you before the AI supplier, and a trucker delivers them.

## Rules the server enforces
- **Position:** the plot's position is the player's position as the server sees it.
- **Ownership:** only the owner, standing next to the plot, can water, harvest or clear it.
- **One harvest per plot:** the plot is claimed in the database first. If the inventory is full, the claim is undone.
- **Server values:** prices, yields and growth come from config and timestamps, never from the client.
- **Ledger keys:**
  - each market sale is paid once under its own key;
  - a seed purchase is charged first and refunded under its own key if the seeds don't fit.
- **Rate limit:** at most one request per 750 ms per player.

## Data
- **Table:** `pf_farm_plots`, created by migration v1 (`pfm-core` migrations).
- **Items:** missing seed and produce items are registered at start. pf-restaurants defines the produce items when it runs.

## Tests
`[qb]/tests/realdb_specs/farming_realdb_spec.lua` (real MariaDB).
