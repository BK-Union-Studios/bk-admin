Config = {}

Config.Locale = 'en' -- 'de' or 'en'

-- UI Settings
Config.UIPosition = 'right' -- 'left' or 'right'
Config.UITransparency = 0.90 -- 0.0 to 1.0
Config.LogoText = { main = "ADMIN", sub = "PANEL" }
Config.FadeSpeed = 0.2 -- Seconds

-- Design (Colors)
Config.Colors = {
    ['primary'] = '#3A7CA5', -- Blue highlight
    ['secondary'] = '#0a0a0a', -- Background
    ['danger'] = '#a53a3a', -- Red buttons / Ban
    ['success'] = '#2ecc71', -- Green / Success
    ['warning'] = '#f1c40f', -- Yellow / Warning
}

Config.OpenCommand = "openadmin"
Config.DefaultKey = "F1" -- Default key mapping

Config.NoClip = {
    DefaultSpeed = 0.5,
    MaxSpeed = 5.0,
    SpeedStep = 0.5, -- Speed increment with mouse wheel
    ShowSpeedNotify = true
}

Config.Weather = {
    TransitionTime = 120.0, -- Seconds
    AutoSyncOnJoin = true
}

Config.Time = {
    TransitionTime = 120.0, -- Seconds
    Interval = 10 -- Minimum ms between ticks (Advanced)
}

-- Auto-Sync on Resource Start
Config.AutoSyncOnStart = false -- Set to false to prevent auto time/weather sync when resource starts or client joins

Config.Permissions = {
    ['admin'] = true,
    ['god'] = true
}

-- Examples:
-- Config.TrustedLicenses = { ["license:yourlicense"] = "god" }
-- Config.TrustedServerIds = { [42] = "god", [7] = "admin" }
Config.TrustedLicenses = {}
Config.TrustedServerIds = {}

-- Whether to also use the framework's notify (QBX/QBCore compatible) in addition to the small NUI notify.
-- Set to `false` to suppress framework notifications and only show the admin NUI notify.
Config.UseFrameworkNotify = false

Config.Duty = {
    EnablePedSwitch = true,
    EnableTag = true,
    Models = {
        ['admin'] = 's_m_m_chemsec_01', 
        ['god'] = 'u_m_m_jesus_01', 
    },
    Tags = {
        ['admin'] = "~b~[ADMIN]",
        ['god'] = "~y~[GOD]"
    },
    TagRange = 20.0,
    TagScale = 0.35
}

Config.ESP = {
    Enabled = true,
    Range = 50.0,
    ShowNames = true,
    ShowIDs = true,
    Color = { r = 255, g = 255, b = 255, a = 215 },
    Scale = 0.35,
    VerticalOffset = 1.1
}

Config.Teleport = {
    FadeTime = 0.5, -- Seconds
    LoadTime = 2.0, -- Seconds
    InvisibleDuringLoad = true,
    NotifyOnSuccess = true
}

Config.Bans = {
    Reasons = {
        "RDM", "VDM", "Fail-RP", "Combat Log", "Cheating", "Trolling", "Insulting"
    },
    Durations = {
        { label = "1 Day", days = 1 },
        { label = "3 Days", days = 3 },
        { label = "1 Week", days = 7 },
        { label = "1 Month", days = 30 },
        { label = "Permanent", days = 0 },
    },
    CleanupInterval = 3600 -- seconds
}

Config.Announcements = {
    Duration = 5.0, -- Seconds
    Title = "Announcement",
    Color = '#3A7CA5'
}

-- Webhook Logging
Config.Logs = {
    Enabled = true,
    WebhookURL = "your_webhook_url_here",
    BotName = "bk_admin Logs",
    Color = 3832997, -- Decimal color code
    Categories = {
        AdminActions = true,  -- Duty, NoClip, God, Vanish, Spectate, etc.
        PlayerActions = true, -- Teleport, Bring, Heal, Revive, Kick, Ban, Freeze, Money, Items, Weapons, Job, Rank
        WorldActions = true,  -- Weather, Time, Blackout, Waves, Density
        ServerActions = true, -- Announcements, Mass Heal/Teleport, Private Messages
    }
}

Config.TeleportPresets = {
    ['cat_authorities'] = {
        { name = "Mission Row PD", coords = vector3(441.1, -982.5, 30.6) },
        { name = "Pillbox Hospital", coords = vector3(299.1, -584.6, 43.2) },
    },
    ['cat_business'] = {
        { name = "Legion Square", coords = vector3(154.1, -929.1, 30.6) },
        { name = "PDM", coords = vector3(-29.1, -1104.5, 26.4) },
    },
    ['cat_crime'] = {
        { name = "Vancity", coords = vector3(124.1, -1929.1, 20.6) },
    },
    ['cat_hotspots'] = {
        { name = "Sandy Shores Airport", coords = vector3(1733.4, 3292.5, 41.1) },
    }
}

Config.Vehicles = {
    MaxFuelOnSpawn = true,
    EngineOnOnSpawn = true,
    RepairCleansDirt = true
}

Config.DefaultWeathers = {
    "EXTRASUNNY", "CLEAR", "CLEARING", "OVERCAST", "SMOG", "FOGGY", 
    "CLOUDS", "RAIN", "THUNDER", "SNOW", "BLIZZARD", "SNOWLIGHT", 
    "XMAS", "HALLOWEEN",
}

Config.DefaultTimes = {
    "00:00", "01:00", "02:00", "03:00", "04:00", "05:00", "06:00", "07:00", 
    "08:00", "09:00", "10:00", "11:00", "12:00", "13:00", "14:00", "15:00", 
    "16:00", "17:00", "18:00", "19:00", "20:00", "21:00", "22:00", "23:00",
}
