local M = {}

local UPGRADE_HINT = "Please upgrade slang-server and possibly also this plugin."
local SOURCE_FILETYPES = { "verilog", "systemverilog" }
local version_info = require("slang-server.version")

---@param bufnr integer
---@return vim.lsp.Client?
function M.get_client(bufnr)
   for _, client in pairs(vim.lsp.get_clients({ bufnr = bufnr })) do
      local server_name = client.server_info and client.server_info.name
      if server_name == "slang-server" or client.name == "slang-server" or client.name == "slang_server" then
         return client
      end
   end
   return nil
end

---@return integer bufnr
function M.get_source_context()
   local bufnr = vim.api.nvim_get_current_buf()
   if M.get_client(bufnr) then
      return bufnr
   end

   local util = require("slang-server.util")
   local source_win = util.last_win({ buflisted = true, filetype = SOURCE_FILETYPES })
   if source_win and M.get_client(source_win.bufnr) then
      return source_win.bufnr
   end

   local source_buf = util.last_buf({ buflisted = true, filetype = SOURCE_FILETYPES })
   if source_buf and M.get_client(source_buf.bufnr) then
      return source_buf.bufnr
   end

   return bufnr
end

-- Client IDs are unique for the Neovim session, so these caches can outlive
-- individual buffer attachments without being confused with a later client.
---@type table<integer, table<string, true>>
local client_cache = {}

---@type table<integer, true>
local warned_clients = {}

---@param client vim.lsp.Client
---@return boolean ok, string? err_msg
function M.version_compatible(client)
   local server_version = client.server_info and client.server_info.version
   if not server_version then
      return false, "slang-server: server does not report its version. " .. UPGRADE_HINT
   end

   local compatible = version_info.major_minor_at_least(server_version, version_info.VERSION)
   if compatible == nil then
      return false,
         string.format(
            "slang-server: could not parse server version '%s'. %s",
            vim.trim(server_version),
            UPGRADE_HINT
         )
   elseif not compatible then
      local major, minor = version_info.parse(version_info.VERSION)
      return false,
         string.format(
            "slang-server: server version %s is older than the client requirement %d.%d.x. "
               .. "Please upgrade slang-server.",
            vim.trim(server_version),
            major,
            minor
         )
   end
   return true, nil
end

---@param client vim.lsp.Client
function M.notify_version(client)
   if warned_clients[client.id] then
      return
   end
   warned_clients[client.id] = true

   local ok, err = M.version_compatible(client)
   if not ok then
      vim.notify(err, vim.log.levels.WARN)
   end
end

---Validate a client's static info and return its supported-command set.
---@param client vim.lsp.Client
---@return table<string, true>? commands, string? err_msg
local function get_info(client)
   local cmds = client_cache[client.id]
   if cmds then
      return cmds, nil
   end

   local compatible, version_err = M.version_compatible(client)
   if not compatible then
      return nil, version_err
   end

   local ecp = client.server_capabilities and client.server_capabilities.executeCommandProvider
   if not (ecp and ecp.commands) then
      return nil, "slang-server: server does not advertise executeCommandProvider. " .. UPGRADE_HINT
   end

   cmds = {}
   for _, value in ipairs(ecp.commands) do
      cmds[value] = true
   end
   client_cache[client.id] = cmds
   return cmds, nil
end

---@param bufnr integer
---@param required_commands string[]
---@return boolean ok, string? err_msg
function M.check(bufnr, required_commands)
   local client = M.get_client(bufnr)
   if not client then
      return false, "slang-server: no slang-server LSP client attached. " .. UPGRADE_HINT
   end

   local cmds, err = get_info(client)
   if not cmds then
      return false, err
   end

   for _, command in ipairs(required_commands) do
      if not cmds[command] then
         return false,
            string.format("slang-server: server does not support LSP command '%s'. %s", command, UPGRADE_HINT)
      end
   end

   return true, nil
end

---@param bufnr integer
---@param required_commands string[]
---@return boolean
function M.check_or_notify(bufnr, required_commands)
   local ok, err = M.check(bufnr, required_commands)
   if not ok then
      vim.notify(err, vim.log.levels.ERROR)
      return false
   end
   return true
end

---@param bufnr integer
---@param command string
---@return boolean ok, string? err_msg
function M.command_supported(bufnr, command)
   return M.check(bufnr, { command })
end

return M
