Config                        = {}

-- 'esx', 'qb', or 'qbox'
Config.Framework              = 'esx'
Config.ESXGroups              = { 'admin', 'superadmin' }
Config.QBPermissions          = { 'admin', 'god' }
Config.QBOXPermissions        = { 'admin', 'god' }

Config.OpenPresent            = {
    enabled  = true,
    duration = 5000,
    label    = 'Opening present...',
    anim     = {
        dict = "mini@repair",
        clip = "fixing_a_player",
        flag = 49,
    }
}

Config.DeleteDistance         = 5.0

Config.NotifyTitle            = 'Present'
Config.NoPermissionMessage    = 'You do not have permission to manage presents.'
Config.NoRewardsMessage       = 'No rewards configured.'
Config.PresentTakenMessage    = 'This present was already taken.'
Config.InventoryFullMessage   = 'Your inventory is full.'
Config.ReceivedMessage        = 'You received %sx %s.'
Config.ProcessingMessage      = 'This present is being opened by someone else.'
Config.NoPresentNearbyMessage = 'No present nearby.'
Config.PresentDeletedMessage  = 'Deleted present ID %d.'
Config.PresentBlipsOnMessage  = 'Present blips enabled.'
Config.PresentBlipsOffMessage = 'Present blips disabled.'
Config.PresentExpiredMessage  = 'This present is empty ha-haa!'

-- /presentcreate (no args) → random prop, no expiry
-- /presentcreate 1 → prop index 1, no expiry
-- /presentcreate 1 72 → prop index 1, expires in 72 hours
-- /presentcreate prop_xmas_gift_01 24 → literal prop name, expires in 24 hours
-- /presentcreate random 48 or /presentcreate r 48 → random prop, expires in 48 hours
-- /presentdelete
-- /presentlocate - ON/OFF
-- /presentcleanexpired
-- /presentcleaneup -- deletes all presents

