# PF Government - Comprehensive Government Framework

## 🎯 Overview

PF Government is a complete city governance system for QBCore FiveM servers. It provides centralized control over:

- **Treasury Management** - City funds tracking and transactions
- **Tax System** - Configurable tax rates and automatic collection
- **Budget Management** - Department budgets with spending tracking
- **Laws & Policy** - Law creation, publishing, and MDT integration
- **Licenses & Permits** - Citizen and business licensing system
- **Utilities & Services** - Power/water management with cutoff capabilities
- **Bills & Fines** - Comprehensive billing system with late fees
- **Business Oversight** - Revenue tracking and compliance monitoring
- **Staff Management** - Government employee permissions
- **Audit Logs** - Immutable action tracking for accountability

## 📦 Installation

### 1. Database Setup

Run the SQL installation script:

```sql
-- Execute the file: sql/install.sql
```

This creates all necessary tables:
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

### 2. Resource Installation

1. Copy `pf-government` folder to `resources/[pfscripts]/`
2. Add to `server.cfg`:

```cfg
ensure pf-government
```

### 3. Configuration

Edit `config.lua` to customize:

- Government job name and grades
- Role-based permissions
- Tax rate limits
- Budget settings
- License types and fees
- Utility billing amounts
- Integration toggles

## 🏛️ Features

### Treasury System

- Centralized city treasury account
- Real-time balance tracking
- Transaction logging
- Low balance warnings
- Deposit/withdrawal audit trail

### Tax System

Configurable tax types:
- Income tax (paychecks)
- Business tax (revenue)
- Property tax
- Vehicle registration fees
- License fees
- Sales tax
- Fuel tax

Features:
- Min/max rate enforcement
- Server-side validation
- Auto-collection support
- Real-time revenue tracking

### Budget System

- Department-specific budgets
- Weekly/custom reset intervals
- Spending tracking
- Budget allocation logging
- Automatic reset system

Supported departments:
- Police Department
- Emergency Medical Services
- Department of Transportation
- Utilities & Public Works
- Government Operations

### Laws & Policy

- Draft, publish, and repeal laws
- Law categories and organization
- Penalty and fine ranges
- **MDT Integration** - Auto-sync laws to Police MDT
- Full text content with rich text editor
- Status tracking (draft/active/repealed)

### Licenses & Permits

**Citizen Licenses:**
- Drivers License
- Firearms License
- Hunting License
- Fishing License
- Work Permit
- Concealed Carry Permit
- Pilots License

**Business Licenses:**
- General Business License
- Restaurant License
- Mechanic Shop License
- Vehicle Dealership License
- Towing License
- Taxi Service License
- Bar & Liquor License
- Nightclub License
- Firearms Dealer License

Features:
- License issuance and renewal
- Expiration tracking
- Suspension and revocation
- Auto-billing for fees

### Utilities & Services

- Property and business utility accounts
- Power and water service control
- Service disconnection for non-payment
- Automatic billing
- Delinquency tracking
- Restoration with payment

### Bills & Fines

Bill types:
- Fines
- Taxes
- Utility bills
- License fees
- Invoices
- Other

Features:
- Due date tracking
- Late fee calculation
- Payment status (unpaid/partial/paid/delinquent)
- Automatic escalation
- Bill waiving capability

### Business Oversight

Mayor can monitor:
- Business revenue statistics
- Employee counts
- Tax compliance
- License status
- Suspicious revenue spikes
- Business registry

Features:
- Compliance status flags
- Business registration
- Revenue tracking
- Tax payment history
- Automated oversight alerts

### Staff Management

- Role-based access control
- Permission management
- Staff directory
- Appointment tracking
- Activity logging

### Audit Logs

Immutable logging system:
- All sensitive actions logged
- Searchable by action type, actor, target, date
- Retention policy support
- Statistics and reporting
- Cannot be modified or deleted

## 🔧 Configuration

### Role Permissions

Configure in `config.lua`:

```lua
Config.Roles = {
    [4] = { name = 'Mayor', permissions = { 'all' } },
    [3] = { name = 'Deputy Mayor', permissions = { 'laws', 'taxes', 'budgets', 'licenses', 'utilities', 'fines', 'staff', 'businesses', 'audit' } },
    [2] = { name = 'Treasurer', permissions = { 'budgets', 'taxes', 'fines', 'audit', 'businesses' } },
    [1] = { name = 'Clerk', permissions = { 'licenses', 'fines', 'audit' } },
    [0] = { name = 'Utility Manager', permissions = { 'utilities', 'audit' } }
}
```

Available permissions:
- `all` - Full access
- `laws` - Law management
- `taxes` - Tax administration
- `budgets` - Budget control
- `licenses` - License issuance
- `utilities` - Utility services
- `fines` - Billing and fines
- `staff` - Staff management
- `businesses` - Business oversight
- `audit` - Audit log access
- `dashboard` - Dashboard view
- `settings` - System settings

## 📡 Exports

### For Other Scripts

The government script provides comprehensive exports for integration:

```lua
-- Laws
exports['pf-government']:GetActiveLaws()

-- Licenses
exports['pf-government']:HasLicense(citizenid, licenseType)
exports['pf-government']:GetBusinessLicenseStatus(businessId)

-- Utilities
exports['pf-government']:HasPower(propertyId)
exports['pf-government']:HasBusinessPower(businessId)

-- Taxes
exports['pf-government']:GetTaxRates()
exports['pf-government']:GetTaxRate(taxType)

-- Bills
exports['pf-government']:CreateBill(targetType, targetId, amount, billType, dueDate, description)
exports['pf-government']:PayBill(billId, amount, paidBy)

-- Business Registration
exports['pf-government']:RegisterBusiness(businessId, businessName, businessType, ownerId, ownerName)
exports['pf-government']:UpdateBusinessRevenue(businessId, amount)

-- Treasury
exports['pf-government']:GetTreasuryBalance()
exports['pf-government']:DepositToTreasury(amount, source, description)
exports['pf-government']:WithdrawFromTreasury(amount, reason, performedBy)
```

## 🔗 Integration Examples

### Restaurant Script Integration

In your restaurant script:

```lua
-- Register restaurant with government
exports['pf-government']:RegisterBusiness(
    restaurantId,
    restaurantName,
    'restaurant',
    ownerId,
    ownerName
)

-- Track revenue (triggers business tax)
exports['pf-government']:UpdateBusinessRevenue(restaurantId, saleAmount)

-- Check if restaurant has power
local hasPower = exports['pf-government']:HasBusinessPower(restaurantId)
if not hasPower then
    -- Service disconnected, can't operate
end
```

### Housing Script Integration

```lua
-- Register property
exports['pf-government']:RegisterProperty(propertyId, propertyName, ownerId, ownerName)

-- Check utilities
local hasPower = exports['pf-government']:HasPower(propertyId)
local hasWater = exports['pf-government']:PropertyHasWater(propertyId)
```

### MDT Law Sync

Laws automatically sync to Police MDT when published. Configure in `config.lua`:

```lua
Config.Laws.MDTIntegration = {
    enabled = true,
    resource = 'pf-policemdt',
    syncOnPublish = true,
    syncOnUpdate = true,
    syncOnRepeal = true
}
```

## 🎮 Commands

- `/gov` - Open government system
- `/government` - Open government system
- `/cityhall` - Open government system

## 🖥️ UI Features

The Windows 11-style interface includes:

- **Lockscreen** with password protection
- **Desktop** with application icons
- **Start Menu** with all applications
- **Taskbar** with app switcher and system tray
- **Multi-window system** with draggable, resizable windows

### City Hall Program

Full government control panel with tabs:
- Dashboard - Overview and statistics
- Laws & Policy - Law management
- Taxes & Fees - Tax configuration
- Budgets - Department budgets
- Licenses & Permits - License issuance
- Utilities & Services - Service control
- Fines & Collections - Bill management
- Government Staff - Staff administration
- Audit Log - Action history
- Settings - System configuration

### Businesses Program

Mayor oversight tool:
- Business registry
- Revenue reports
- Tax compliance
- Employee tracking
- Compliance actions
- Suspicious activity flags

## 🛡️ Security Features

- **Server-side validation** for all actions
- **Permission checks** on every request
- **Immutable audit logs** cannot be edited
- **Rate/range validation** prevents abuse
- **SQL injection protection** via oxmysql
- **Action logging** for accountability

## 📊 Database Schema

All tables use `utf8mb4_unicode_ci` collation and include:
- Indexes for performance
- Timestamps for tracking
- Foreign key conceptual relationships
- Appropriate data types

## 🐛 Troubleshooting

### UI Not Opening

1. Check you have government job: `Config.GovernmentJob`
2. Verify grade permissions in `Config.Roles`
3. Check F8 console for errors

### Laws Not Syncing to MDT

1. Ensure MDT resource is started
2. Verify `Config.Laws.MDTIntegration.enabled = true`
3. Check MDT resource name matches config
4. Confirm MDT has `SyncLaws` export function

### Taxes Not Collecting

1. Enable auto-collection: `Config.Taxes.AutoCollection.enabled = true`
2. Verify integration hooks are configured
3. Check that tax rates are > 0

## 📝 TODO / UI Completion

The backend framework is **100% complete**. Remaining UI tasks:

1. Copy UI files from `pf-governmentuionly/` to `html/`:
   - index.html
   - style.css
   - script.js
   - rte.js
   - rte.css
   - games.js

2. Enhance UI with actual government features:
   - Connect dashboard to real data
   - Implement all City Hall tabs
   - Create Business oversight interface
   - Connect all forms to NUI callbacks

3. Test all features end-to-end

## 📜 License

Copyright © 2026 PF Scripts. All rights reserved.

## 🤝 Support

For support, contact PF Scripts support team.

---

**Built with ❤️ by PF Scripts**
