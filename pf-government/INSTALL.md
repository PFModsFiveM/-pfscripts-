# PF Government Installation Guide

This guide is written for the actual resource in this repository. Follow it in order. If you skip the SQL import, the government job, or the dependent resource restarts, parts of the script will appear to work while taxes, treasury syncing, or access control do not.

## What This Resource Needs

PF Government requires all of the following before it will work correctly:

- A working QBCore server
- `oxmysql` started and connected to the same database your server uses
- `qb-core` started before `pf-government`
- A `government` job in QBCore, or a matching custom job name set in `config.lua`
- The PF Government SQL imported from `pf-government/sql/install.sql`
- If treasury syncing is enabled, a working `qb-banking`
- If you want to use the world computer target, `qb-target`

## Important Before You Start

- Do not use the top-level `pf_custom_install.sql` file for this resource. That file does not create the PF Government tables.
- The correct SQL file is `resources/[pfscripts]/pf-government/sql/install.sql`.
- The `enable_sales_tax.sql` file is only for older installs that already have PF Government tables but have the `sales` tax row disabled. A fresh install does not need it.
- The tax system now charges from the actual purchase resources. If you move only `pf-government` to another server and do not also deploy the matching patched purchase resources, the UI will load but taxes will not be collected in those flows.

## Step 1: Place the Resource

Make sure the folder is here:

```text
resources/[pfscripts]/pf-government/
```

The resource name must remain `pf-government` unless you also update every cross-resource export call that points to it.

## Step 2: Import the Database

Import this file into the same database used by your server:

```text
resources/[pfscripts]/pf-government/sql/install.sql
```

That file creates the full PF Government schema, including:

- `pf_gov_treasury`
- `pf_gov_taxes`
- `pf_gov_budgets`
- `pf_gov_laws`
- `pf_gov_licenses`
- `pf_gov_bills`
- `pf_gov_utilities`
- `pf_gov_businesses`
- `pf_gov_staff`
- `pf_gov_audit_log`
- `pf_gov_announcements`
- `pf_gov_transactions`

After import, verify it with:

```sql
SHOW TABLES LIKE 'pf_gov%';
```

You should see 12 tables.

## Step 3: Add the Government Job to QBCore

By default the resource expects this job name:

```lua
Config.GovernmentJob = 'government'
```

Make sure that job exists in [qb-core/shared/jobs.lua](../../[qb]/qb-core/shared/jobs.lua) or in your actual QBCore job definition file.

Example:

```lua
['government'] = {
    label = 'Government',
    type = 'government',
    defaultDuty = true,
    offDutyPay = false,
    grades = {
        ['0'] = { name = 'Utility Manager', payment = 50 },
        ['1'] = { name = 'Clerk', payment = 75 },
        ['2'] = { name = 'Treasurer', payment = 100 },
        ['3'] = { name = 'Deputy Mayor', payment = 150 },
        ['4'] = { name = 'Mayor', payment = 200, isboss = true },
    },
},
```

If you use a different job name:

- Change `Config.GovernmentJob`
- Change `Config.AccessControl.AllowedJobs`
- Change `Config.Treasury.SocietyAccount` if you want the treasury to sync to a different job account

## Step 4: Configure `config.lua`

Open `resources/[pfscripts]/pf-government/config.lua` and review these sections before first start.

### Core settings

Keep these correct for your framework:

```lua
Config.Framework = 'qbcore'
Config.FrameworkResourceName = 'qb-core'
```

### Government access

Default access behavior is:

- Job required: `true`
- Location required: `false`
- Item required: `false`
- UI password required: `false`

That means any player with the government job can open the UI from the command immediately after installation.

### Treasury settings

By default:

```lua
Config.Treasury.UseSocietyAccount = true
Config.Treasury.SocietyAccount = 'government'
Config.Treasury.StartingBalance = 100000
```

What that means:

- If `qb-banking` is running, PF Government will try to use the `government` job account as the live treasury.
- If the account does not exist, it will try to create it.
- If you do not use `qb-banking`, set `Config.Treasury.UseSocietyAccount = false` and PF Government will use the `pf_gov_treasury` table instead.

### Tax settings

The tax system seeds and manages these default tax types:

- `income`
- `business`
- `property_transfer`
- `vehicle_registration`
- `vehicle_purchase`
- `sales`
- `supplies`

The mayor-facing min and max limits come from `Config.Taxes.Enforcement`. If you want to change what can be set in the UI, edit that section and restart `pf-government`.

Example:

```lua
Config.Taxes.Enforcement = {
    sales = { min = 0.00, max = 50.00 },
    vehicle_purchase = { min = 0.00, max = 20.00 },
    property_transfer = { min = 0.00, max = 20.00 },
    supplies = { min = 0.00, max = 20.00 }
}
```

### MDT integration

If you use `pf-policemdt`, confirm this matches your MDT resource name:

```lua
Config.Laws.MDTIntegration.resource = 'pf-policemdt'
Config.Integrations.MDT.resource = 'pf-policemdt'
```

### Optional world access point

The client script spawns a temporary government computer prop and adds a `qb-target` interaction if `qb-target` is started. If you do not use `qb-target`, the script still works through commands.

## Step 5: Add the Resource to `server.cfg`

At minimum, make sure these start before PF Government:

```cfg
ensure oxmysql
ensure pfm-core
ensure pfm-banking
ensure pfm-target
ensure pf-government
```

Notes:

- `qb-banking` is only required if `Config.Treasury.UseSocietyAccount = true`.
- `qb-target` is optional.
- `pf-government` should be running before players try to use any resource that calls its exports.

## Step 6: Make Sure the Tax-Connected Resources Are Deployed

PF Government does not magically tax every purchase script on your server. In this repository, live tax charging has been wired into these resource flows:

- `qb-inventory` instant purchases
- `pf-stores` cart checkout
- `qb-vehiclesales` used vehicle purchase flow
- `qb-houses` property purchase flow
- `pf-restaurants` supplies ordering flow

That means all of these resource copies need to be the ones from this workspace if you want those taxes to actually charge:

- `resources/[qb]/qb-inventory`
- `resources/[pfscripts]/pf-stores`
- `resources/[qb]/qb-vehiclesales`
- `resources/[qb]/qb-houses`
- `resources/[pfscripts]/pf-restaurants`

If your live server uses different shop, vehicle, property, or business resources, you will need to integrate them to PF Government as well. The base PF Government install alone only gives you the government system itself, not universal purchase taxation.

## Step 7: Start or Restart Resources in the Right Order

After the SQL import and config review, restart the relevant resources.

Recommended restart order:

```text
restart pfm-core
restart pfm-banking
restart pf-government
restart pfm-inventory
restart pf-stores
restart pfm-vehiclesales
restart pfm-houses
restart pf-restaurants
```

If you do not want to restart everything, at least restart `pf-government` and every resource that directly calls its tax exports.

## Step 8: Assign Your First Mayor

Use your admin job command, for example:

```text
/setjob [id] government 4
```

Grade `4` maps to Mayor by default.

After assigning the job, have the player relog or refresh their job if your admin tool does not do that automatically.

## Step 9: Open the UI and Confirm Access

Default commands:

- `/gov`
- `/government`
- `/cityhall`

What should happen:

- A player with the government job can open the desktop UI.
- A player without the job is denied access.
- If `Config.AccessControl.RequireLocation = true`, the player must also be inside one of the configured locations.
- If `Config.AccessControl.RequireItem = true`, the configured item is also required.

## Step 10: Verify the Install Actually Works

Do this test pass after installation.

### Government UI checks

Log in as the Mayor and verify:

- The UI opens with `/gov`
- Dashboard loads without errors
- Treasury shows a live value instead of a hardcoded placeholder
- Taxes page lists the configured tax types
- Changing the sales tax in the UI saves and stays changed after refresh

### Treasury checks

Verify one of these is true:

- If `UseSocietyAccount = true`, the treasury matches the `government` account in `qb-banking`
- If `UseSocietyAccount = false`, the treasury balance is stored in `pf_gov_treasury`

### Tax collection checks

Run at least one transaction in each flow you use:

- Buy an item from an instant-purchase shop
- Buy items through a cart-based store
- Buy a vehicle from the used vehicle flow
- Buy a house through `qb-houses`
- Order supplies through `pf-restaurants`

For each test, confirm:

- The player is charged `subtotal + tax`
- The transaction is blocked if the player cannot afford the full total
- The tax amount goes into the government treasury
- The UI shows the updated treasury amount after refresh

## Common Setup Mistakes

### The UI opens but data is missing

Usually caused by not importing `sql/install.sql`.

### The UI says access denied

Check all of these:

- The player has the correct job name
- The job grade exists in `Config.Roles`
- `Config.AccessControl.RequireLocation` is not blocking access
- `Config.AccessControl.RequireItem` is not blocking access

### The treasury is wrong or does not move

Check all of these:

- `qb-banking` is running if society sync is enabled
- `Config.Treasury.SocietyAccount` matches the intended job account
- The transaction flow you tested is actually one of the patched resources

### Taxes stay at zero or never change from the UI

Check all of these:

- `pf-government` has been restarted after config changes
- The `sales` row exists in `pf_gov_taxes`
- The purchase resource you tested is one of the integrated resources
- You are not testing an unpatched third-party shop script

### You imported the wrong SQL file

If you imported only `pf_custom_install.sql`, PF Government is not installed. Import `pf-government/sql/install.sql`.

## Useful Exports for Additional Integrations

If you need to hook more scripts into PF Government, these are the main exports already available:

```lua
exports['pf-government']:GetTaxRates()
exports['pf-government']:GetTaxRate(taxType)
exports['pf-government']:CalculateTax(amount, taxType)
exports['pf-government']:GetSalesTaxBreakdown(subtotal)
exports['pf-government']:CollectTax(subtotal, taxType, targetType, targetId, collectedBy)
exports['pf-government']:GetTreasuryBalance()
exports['pf-government']:DepositToTreasury(amount, source, description)
exports['pf-government']:WithdrawFromTreasury(amount, reason, performedBy)
exports['pf-government']:GetActiveLaws()
exports['pf-government']:HasLicense(citizenid, licenseType)
exports['pf-government']:GetBusinessLicenseStatus(businessId)
exports['pf-government']:HasPower(propertyId)
exports['pf-government']:HasBusinessPower(businessId)
exports['pf-government']:CreateBill(targetType, targetId, amount, billType, dueDate, description)
exports['pf-government']:PayBill(billId, amount, paidBy)
exports['pf-government']:RegisterBusiness(businessId, businessName, businessType, ownerId, ownerName)
exports['pf-government']:UpdateBusinessRevenue(businessId, amount)
```

## Final Checklist

- [ ] `sql/install.sql` was imported successfully
- [ ] `pf_gov_*` tables exist in the database
- [ ] `government` job exists in QBCore or `config.lua` was changed to your custom job name
- [ ] `qb-core` and `oxmysql` start before `pf-government`
- [ ] `qb-banking` is running if society treasury sync is enabled
- [ ] `pf-government` was restarted after configuration changes
- [ ] Any purchase resources you expect to tax are the integrated versions
- [ ] A Mayor can open the UI and change taxes
- [ ] A test purchase charges tax and increases treasury

Version: 1.0.0
Last updated: March 2026
