-- StarterPlayerScripts/Client.client.lua
-- Bootstrap only. All logic lives in Modules.

local UIManager = require(script.Modules.UIManager)
local ForgeClient = require(script.Modules.ForgeClient)

UIManager.init()
ForgeClient.init(UIManager)
