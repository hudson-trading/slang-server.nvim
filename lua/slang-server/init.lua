-- Main module file

local config = require("slang-server._core.config")
local version_info = require("slang-server.version")

---@class SlangModule
---@field version string
---@field add_client_capabilities fun(client_capabilities: table?): table
local M = {}
M.version = version_info.VERSION
M.add_client_capabilities = version_info.add_client_capabilities

---@param opts slang-server.config.Configuration?
M.setup = function(opts)
   config.update(opts)
   version_info.setup()
end

return M
