-- Define the current version of your MLO
local currentVersion = "1.0.2"

-- The URL to check the latest version (e.g., from GitHub or your website)
local versionCheckUrl = "https://raw.githubusercontent.com/PFModsFiveM/PoliceMDT/refs/heads/main/version.json" -- replace with your actual URL

-- Function to check the version
Citizen.CreateThread(function()
    PerformHttpRequest(versionCheckUrl, function(statusCode, response, headers)
        if statusCode == 200 then
            local data = json.decode(response)
            local latestVersion = data.version

            -- Compare the current version with the latest version
            if latestVersion ~= currentVersion then
                -- Notify in F8 console
                print("^0[UPDATE] ^8An update is available for PF MODS PF-PoliceMDT! Current version: " .. currentVersion .. ", Latest version: " .. latestVersion)
                print("^0[UPDATE] ^8An update is available for PF MODS PF-PoliceMDT! Current version: " .. currentVersion .. ", Latest version: " .. latestVersion)
                print("^0[UPDATE] ^8An update is available for PF MODS PF-PoliceMDT! Current version: " .. currentVersion .. ", Latest version: " .. latestVersion)

                -- Optionally notify players
                TriggerClientEvent('chat:addMessage', -1, {
                    color = {255, 0, 0},
                    multiline = true,
                    args = {"PF MODS PF-PoliceMDT Update", "An update is available! Please update to version " .. latestVersion}
                })
            else
                print("^8[PF MODS PF-PoliceMDT] ^5 You're using the latest version: " .. currentVersion)
            end
        else
            print("^1[ERROR] ^0Failed to check for updates. Status Code: " .. statusCode)
        end
    end, "GET", "", {})
end)
