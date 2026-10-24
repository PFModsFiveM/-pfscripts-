# Government Announcements to Email Sync

## Overview
Government announcements from **pf-government** are now automatically synced to emails in **pf-computer** in real-time.

## What Was Added

### 1. **pf-computer: gov_announcements_sync.lua** (NEW)
New integration file that handles syncing government announcements to emails:
- Listens for government announcement events
- Creates/updates/deletes emails automatically
- Sends announcements to all government employee mailboxes
- Includes live sync checking capability

### 2. **pf-computer: fxmanifest.lua** (MODIFIED)
Added `gov_announcements_sync.lua` to server scripts for auto-loading

### 3. **pf-government: server/callbacks.lua** (MODIFIED)
Enhanced announcement creation to trigger sync events:
- `gov:createAnnouncement` - Now triggers email sync
- `announcement:create` - Now triggers email sync  
- `announcement:delete` - Now triggers email deletion sync

### 4. **pf-government: server/integrations.lua** (MODIFIED)
Added new exports:
- `GetActiveAnnouncements()` - Get all active announcements
- `GetAnnouncement(id)` - Get specific announcement

## How It Works

### Announcement Creation Flow:
1. Government staff creates an announcement via pf-government UI
2. Announcement is stored in `pf_gov_announcements` database table
3. **Sync Event Triggered**: `pf-computer:gov:announcements:sync` event fires
4. pf-computer receives event and:
   - Identifies all government employee email accounts (mailbox ending in `@los-santos.gov`)
   - Creates email in each employee's inbox
   - Emails are marked as unread with `[City Hall]` prefix
   - Metadata stores reference to original announcement ID

### Email Updates:
- When an announcement is modified, the sync system detects duplicate announcements
- Matching emails are updated with new content
- Existing metadata preserves the announcement link

### Email Deletion:
- When an announcement is deleted (set to inactive)
- All linked emails are automatically removed from pf-computer
- System uses metadata to track announcement-to-email relationships

## Features

✅ **Live Sync** - Announcements appear in emails immediately  
✅ **All Employees Get Notified** - Emails sent to all `@los-santos.gov` mailboxes  
✅ **Update Support** - Changes to announcements update emails  
✅ **Deletion Support** - Deleted announcements remove emails  
✅ **Metadata Tracking** - Uses announcement ID for tracking relationships  
✅ **Priority Support** - Server stores announcement priority in email metadata  
✅ **Backward Compatible** - Existing announcement system still works  

## Email Format

**Subject:** `[City Hall] {announcement_title}`  
**From:** `{Author Name}`  
**To:** `{Government Employee Mailbox}`  
**Folder:** Inbox (unread)  
**Metadata:**
- `gov_announcement_id`: Reference to original announcement
- `gov_announcement`: Flag indicating government announcement
- `priority`: Announcement priority level

## Configuration

### Announcement Mailbox (Optional)
Edit in `gov_announcements_sync.lua`:
```lua
local ANNOUNCEMENT_EMAIL_MAILBOX = 'announcements@los-santos.gov'
```

### Sync Check Interval (Optional)
For periodic resync from database (every 30 seconds):
```lua
local SYNC_CHECK_INTERVAL = 30000
```

Enable with: `EnableLiveAnnouncementSync()` (server-side)

## Testing

1. **Start both resources:**
   - pf-government
   - pf-computer

2. **Create an announcement in pf-government:**
   - Open government menu
   - Create announcement with title and content
   - Verify announcement is created

3. **Check emails in pf-computer:**
   - Open computer
   - Go to email application
   - Should see `[City Hall]` email in inbox
   - Email should contain announcement content

4. **Test updates:**
   - Modify announcement in pf-government
   - Email in pf-computer should update automatically

5. **Test deletion:**
   - Delete announcement in pf-government
   - Email should disappear from pf-computer

## Troubleshooting

### Emails Not Appearing
- **Check**: Both resources are started (`/status` command)
- **Check**: Government employees exist with `@los-santos.gov` mailbox
- **Check**: pf-computer console for sync events (enable debug if needed)

### Emails Not Updating
- **Cause**: Metadata might not match if announcement ID changed
- **Solution**: Delete and recreate announcement

### Sync Not Triggering
- **Check**: pf-government callbacks file loaded correctly
- **Check**: `gov_announcements_sync.lua` is loaded in pf-computer
- **Check**: Server console for load errors

## Database Schema

No new tables needed. Integration uses existing structures:
- `pf_gov_announcements` (pf-government) - Original announcements
- `pc_data.json` (pf-computer) - Email storage

Announcement data synced to email metadata for tracking.

## Migration from Old System

If you had the old announcement system:
1. Old emails remain as-is in pf-computer
2. New announcements automatically use sync system
3. Old emails can be manually deleted if desired
4. No conflicts or issues

## Support

For issues or questions:
1. Check that both resources are running
2. Verify `gov_announcements_sync.lua` is in pf-computer folder
3. Check pf-computer fxmanifest includes the new file
4. Review pf-government callbacks for sync event triggers
5. Check server console for errors during resource start

