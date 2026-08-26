-- Main module file

local config = require("slang-server._core.config")
local manager = require("slang-server._core.manager")
local version_info = require("slang-server.version")

---@class SlangModule
---@field version string
---@field before_init fun(params: table)
local M = {}
M.version = version_info.VERSION
M.before_init = manager.before_init

---@param opts slang-server.config.Configuration?
M.setup = function(opts)
   config.update(opts)
   manager.setup()
   manager.ensure_buffer(0)
end

return M
