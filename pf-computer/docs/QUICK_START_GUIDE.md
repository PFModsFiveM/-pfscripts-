# pf-computer Features - Quick Reference Guide

## 🎯 Feature 1: Job Change Detection

### What It Does
Business Manager and Order Supplies now automatically refresh when your job changes.

### How to Test
1. Open Business Manager while manager of a restaurant
2. Change your job to mechanic (or vice versa)
3. UI should automatically update with new business data
4. No script restart needed!

### User Benefits
- Real-time UI updates when switching businesses
- Instant access to correct business data
- No manual refresh or restart required

---

## 💼 Feature 2: Persistent Business Blips

### What It Does
Business blips save to server and automatically recreate on script restart.

### How to Test
1. Start the script
2. Business blips appear in-game at saved locations
3. Restart the script or server
4. Blips reappear automatically
5. No manual setup needed after restart

### Blip Icons by Business Type
- 🍔 **Restaurants** - Burger/Food icon (sprite 52)
- 🔧 **Mechanics** - Wrench icon (sprite 227)

### User Benefits
- Persistent map markers across restarts
- Easy identification of different business types
- No more "where is my business?" after restart

---

## 🍽️ Feature 3: Meal Combo Management

### What It Does
Owners can create meal combinations from existing menu items with custom pricing.

### How to Test

**Create a Meal:**
1. Open Business Manager
2. Click "Menu Management"
3. Click green "Add Meal Item" button
4. Select menu items to include in combo
5. Set custom meal price
6. Click "Create Meal"
7. Meals tab now shows the new combo

**Edit a Meal:**
1. Click "Meals" tab
2. Click edit icon on meal card
3. Modify composition or price
4. Click "Update Meal"

**Delete a Meal:**
1. Click edit icon on meal
2. Click red "Delete Meal" button
3. Confirm deletion

### User Benefits
- Create attractive combo deals
- Bundle items for better profit margins
- Easy meal management interface
- Set custom pricing per combo

---

## 📦 Feature 4: Ingredient Quantity Restrictions

### What It Does
Buns can only be ordered in quantity of 1. All other ingredients allow variable quantities (1-100).

### How to Test

**Ordering Buns:**
1. Open Order Supplies
2. Navigate to shop
3. Find "Regular Bun" or similar
4. Notice it says "Fixed: 1"
5. Try to change quantity → **Cannot change!**

**Ordering Other Ingredients:**
1. Find any non-bun item (beef patty, lettuce, etc.)
2. Use +/- buttons to adjust quantity
3. Can set any amount from 1-100

### Visual Indicators
- **Buns**: Display "Fixed: 1" with disabled controls
- **Other Items**: Show quantity spinners with +/- buttons

### User Benefits
- Prevents accidental bun overbuy
- Enforces business logic constraints
- Clear UI feedback for restrictions

---

## 🎫 Feature 5: Persistent Menu Items

### What It Does
All menu items created in-game are saved to database.

### How to Test
1. Create a new menu item in Business Manager
2. Restart the script/server
3. Item still exists in menu!
4. All properties preserved

### Auto-Save Features
- Item name, category, price, cost
- Ingredients list
- Description
- Availability status

### User Benefits
- No manual database entry needed
- Items survive script restarts
- In-game menu management interface

---

## 🍔 Feature 6: Tab Switching for Menu/Meals

### What It Does
Easy tabbed interface to switch between menu items and meal combos.

### How to Test
1. Open Business Manager
2. Go to "Menu Management"
3. See two tabs: "Items" and "Meals"
4. Click "Items" tab → View menu items
5. Click "Meals" tab → View meal combos
6. Switch back and forth seamlessly

### Associated Features
- **Search bar**: Find items by name
- **Category filter**: Filter by burger, sides, drinks, etc.
- **Add buttons**: Quick access to create new items or meals
- **Quick actions**: Edit/delete buttons on each card

### User Benefits
- Cleaner, organized interface
- Easy management of multiple menu types
- Filter and search capabilities

---

## 📊 Implementation Details

### Files Modified
- ✅ `server.lua` - Added handlers for meals and blips
- ✅ `client.lua` - Added blip loading and job change detection
- ✅ `script.js` - Added meal UI, tab switching, quantity restrictions

### No Breaking Changes
- ✅ All existing features still work
- ✅ Backward compatible with existing data
- ✅ Framework-agnostic (QBCore + ESX supported)

---

## 🔧 Settings & Configuration

### Where to Manage Blips
**In-Game Menu > Business Manager > Settings**
- Set business name
- Set blip color
- Set blip location (click "Set Blip Location" button)

### Where to Create Meals
**In-Game Menu > Business Manager > Menu**
- Click "Add Meal Item" button
- Select existing menu items
- Set combo price
- Click "Create Meal"

### Where to Order with Restrictions
**Order Supplies Window**
- Shop tab shows all items
- Buns: Fixed quantity 1
- All else: Variable 1-100

---

## ❓ Frequently Asked Questions

### Q: Will my blips appear after server restart?
**A:** Yes! Blips are now persistent and automatically load on startup.

### Q: Can I change bun quantity?
**A:** No, buns are restricted to 1 to prevent user error and enforce business logic.

### Q: Do meals save automatically?
**A:** Yes! When you click "Create Meal", it instantly saves to the database.

### Q: What happens if I switch jobs?
**A:** Business Manager automatically updates to show your new business data.

### Q: Can I have different meal prices than item sum?
**A:** Yes! Meal price is independent - set it to maximize profit!

### Q: Will menu items appear after restart?
**A:** Yes! All items are saved to the database and reload automatically.

---

## 🐛 Troubleshooting

### Blips Not Showing?
1. Restart client script
2. Check server console for errors
3. Verify blip data saved in settings

### Meals Not Saving?
1. Check for server errors
2. Verify "Create Meal" button was clicked
3. Reload Business Manager window

### Quantity Restrictions Not Working?
1. Check ingredient names (must contain "bun")
2. Refresh Order Supplies window
3. Check browser console for JS errors

### Tab Switching Broken?
1. Refresh page
2. Check browser console
3. Try clicking menu button again

---

## 📋 Checklist for Full Implementation

- [x] Job change detection implemented
- [x] Blip persistence working
- [x] Business-specific blip icons assigned
- [x] Ingredient quantity restrictions active
- [x] Menu items save to database
- [x] Meal combo creation system ready
- [x] Tab switching UI enabled
- [x] All handlers registered
- [x] No syntax errors
- [x] Framework compatibility confirmed

---

## 🎓 For Developers

### Adding New Features?
All meal/blip handlers follow this pattern:

```lua
handlers['business:meals:xxxx'] = function(source, payload)
    local authorizedBusiness = getAuthorizedBusiness(source, payload.businessId)
    if not authorizedBusiness then
        return { ok = false, error = 'not_authorized' }
    end
    
    -- Your logic here
    
    savePCData()  -- Don't forget to save!
    return { ok = true, data = result }
end
```

### Key Methods in script.js:
- `fetchServer()` - Server communication
- `handleJobChange()` - Job update handling
- `navigateTo()` - UI section navigation
- `uiNotify()` - User notifications

---

## 📞 Support

For issues or questions:
1. Check this guide first
2. Review IMPLEMENTATION_SUMMARY.md for technical details
3. Check server console for errors
4. Check browser console (F12) for JS errors

---

**Version 1.0 - All Features Implemented ✅**

Ready to use! Test and enjoy the enhanced pf-computer experience.
