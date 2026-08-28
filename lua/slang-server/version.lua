local M = {}

M.NAME = "slang-server.nvim"
M.VERSION = "0.2.0"

---@param client_capabilities table?
---@return table
function M.add_client_capabilities(client_capabilities)
   return vim.tbl_deep_extend("force", client_capabilities or {}, {
      experimental = {
         slangClient = {
            name = M.NAME,
            version = M.VERSION,
         },
      },
   })
end

---@param value string?
---@return integer?, integer?, integer?
function M.parse(value)
   if not value then
      return nil, nil, nil
   end

   value = value:match("^%s*(.-)%s*$")
   if value:sub(1, 1) == "v" then
      value = value:sub(2)
   end

   local major, minor, patch, suffix = value:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
   if not major or (suffix ~= "" and suffix:sub(1, 1) ~= "+" and suffix:sub(1, 1) ~= "-") then
      return nil, nil, nil
   end
   return tonumber(major), tonumber(minor), tonumber(patch)
end

---@param have string?
---@param want string?
---@return boolean?
function M.major_minor_at_least(have, want)
   local hmajor, hminor = M.parse(have)
   local wmajor, wminor = M.parse(want)
   if not hmajor or not wmajor then
      return nil
   end
   return hmajor > wmajor or (hmajor == wmajor and hminor >= wminor)
end

local warned_clients = {}

---@param client vim.lsp.Client
function M.notify_if_incompatible(client)
   if warned_clients[client.id] then
      return
   end
   warned_clients[client.id] = true

   local server_version = client.server_info and client.server_info.version
   local compatible = M.major_minor_at_least(server_version, M.VERSION)
   if compatible then
      return
   end

   local message
   if compatible == nil then
      message = server_version and string.format("could not parse server version '%s'", vim.trim(server_version))
         or "server does not report its version"
   else
      local major, minor = M.parse(M.VERSION)
      message = string.format(
         "server version %s is older than the client requirement %d.%d.x",
         vim.trim(server_version),
         major,
         minor
      )
   end
   vim.notify(
      "slang-server: "
         .. message
         .. ". Please upgrade it with your package manager. If you use Mason, run :MasonInstall slang-server.",
      vim.log.levels.WARN
   )
end

local function is_slang_client(client)
   local server_name = client.server_info and client.server_info.name
   return server_name == "slang-server" or client.name == "slang-server" or client.name == "slang_server"
end

local setup_complete = false

function M.setup()
   if setup_complete then
      return
   end
   setup_complete = true

   vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("slang-server.version", { clear = true }),
      callback = function(args)
         local client = vim.lsp.get_client_by_id(args.data.client_id)
         if client and is_slang_client(client) then
            M.notify_if_incompatible(client)
         end
      end,
   })

   for _, client in pairs(vim.lsp.get_clients()) do
      if client.initialized ~= false and is_slang_client(client) then
         M.notify_if_incompatible(client)
      end
   end
end

return M
