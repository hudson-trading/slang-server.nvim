local capabilities = require("slang-server._lsp.capabilities")
local config = require("slang-server._core.config")
local mason = require("slang-server._core.mason")
local version_info = require("slang-server.version")

local M = {}
local setup_complete = false
local prompts = {}
local declined_updates = {}
local install_prompt_declined = false
local pending_buffers = {}
local pending_update_clients = {}
local managed_clients = {}

---@param params table
function M.before_init(params)
   params.capabilities = params.capabilities or {}
   params.capabilities.experimental = params.capabilities.experimental or {}
   params.capabilities.experimental.slangClient = {
      name = version_info.NAME,
      version = version_info.VERSION,
   }
end

local function is_source_buffer(bufnr)
   if not vim.api.nvim_buf_is_valid(bufnr) then
      return false
   end
   local filetype = vim.bo[bufnr].filetype
   return filetype == "verilog" or filetype == "systemverilog"
end

---@param path string
---@param bufnr integer
---@param update_with_mason boolean?
function M.start(path, bufnr, update_with_mason)
   if not config.CONFIG.server.auto_start or not is_source_buffer(bufnr) or capabilities.get_client(bufnr) then
      return
   end

   local command = { path }
   vim.list_extend(command, config.CONFIG.server.args or {})
   local root = vim.fn.getcwd()
   if vim.fs and vim.fs.root then
      root = vim.fs.root(bufnr, config.CONFIG.server.root_markers or {}) or root
   end
   vim.lsp.start({
      name = "slang-server",
      cmd = command,
      root_dir = root,
      before_init = M.before_init,
      on_init = function(client)
         managed_clients[client.id] = { update_with_mason = update_with_mason == true }
         capabilities.notify_version(client)
      end,
      on_exit = function(_, _, client_id)
         managed_clients[client_id] = nil
         pending_update_clients[client_id] = nil
         declined_updates[client_id] = nil
      end,
   }, { bufnr = bufnr })
end

local function configured_path()
   local path = config.CONFIG.server.path
   if path then
      if vim.fn.executable(path) == 1 then
         return path, nil, false
      end
      return nil, "configured server path is not executable: " .. path, false
   end

   path = vim.env.SLANG_SERVER_PATH
   if path and path ~= "" then
      if vim.fn.executable(path) == 1 then
         return path, nil, false
      end
      return nil, "SLANG_SERVER_PATH is not executable: " .. path, false
   end

   path = mason.path()
   if path then
      return path, nil, true
   end

   path = vim.fn.exepath("slang-server")
   if path ~= "" then
      return path, nil, false
   end
   return nil, nil, true
end

local function install_with_mason(force)
   vim.notify((force and "Updating" or "Installing") .. " slang-server with Mason...", vim.log.levels.INFO)
   mason.install(force, function(path, err)
      prompts[force and "update" or "install"] = nil
      if err then
         vim.notify("slang-server.nvim: " .. err, vim.log.levels.ERROR)
         return
      end
      if not path then
         vim.notify("Mason installed slang-server; restart Neovim to use it", vim.log.levels.INFO)
         return
      end

      vim.notify("Mason installed slang-server at " .. path, vim.log.levels.INFO)
      if force then
         local clients = pending_update_clients
         pending_update_clients = {}
         for _, client in pairs(clients) do
            if managed_clients[client.id] then
               local client_id = client.id
               local buffers = vim.lsp.get_buffers_by_client_id(client.id)
               client:stop(true)
               local restart
               restart = function()
                  local retry = false
                  for _, bufnr in ipairs(buffers) do
                     local attached = capabilities.get_client(bufnr)
                     if not attached then
                        M.start(path, bufnr, true)
                     elseif attached.id == client_id then
                        retry = true
                     end
                  end
                  if retry then
                     vim.defer_fn(restart, 100)
                  end
               end
               vim.defer_fn(restart, 100)
            end
         end
      else
         for bufnr in pairs(pending_buffers) do
            M.start(path, bufnr, true)
         end
         pending_buffers = {}
      end
   end)
end

local function prompt_mason(force)
   local key = force and "update" or "install"
   if prompts[key] or (not force and install_prompt_declined) then
      return
   end
   prompts[key] = true

   vim.ui.select({ force and "Update" or "Install", "Not now" }, {
      prompt = force and "The attached slang-server is incompatible. Update it with Mason?"
         or "slang-server was not found. Install it with Mason?",
   }, function(choice)
      if choice == (force and "Update" or "Install") then
         install_with_mason(force)
      else
         prompts[key] = nil
         if force then
            for client_id in pairs(pending_update_clients) do
               declined_updates[client_id] = true
            end
            pending_update_clients = {}
         else
            install_prompt_declined = true
         end
      end
   end)
end

local function check_client(client)
   capabilities.notify_version(client)
   if capabilities.version_compatible(client) or not config.CONFIG.mason.update_on_mismatch then
      return
   end

   local managed = managed_clients[client.id]
   if managed and managed.update_with_mason and not declined_updates[client.id] then
      pending_update_clients[client.id] = client
      prompt_mason(true)
   end
end

function M.install()
   local bufnr = capabilities.get_source_context()
   if is_source_buffer(bufnr) then
      pending_buffers[bufnr] = true
   end
   install_prompt_declined = false
   prompts.install = true
   install_with_mason(false)
end

function M.update()
   local bufnr = capabilities.get_source_context()
   local client = capabilities.get_client(bufnr)
   if client then
      local managed = managed_clients[client.id]
      if not (managed and managed.update_with_mason) then
         vim.notify(
            "slang-server.nvim: update the externally configured slang-server through its existing installation method",
            vim.log.levels.WARN
         )
         return
      end
      declined_updates[client.id] = nil
      pending_update_clients[client.id] = client
   end
   prompts.update = true
   install_with_mason(true)
end

---@param bufnr integer
function M.ensure_buffer(bufnr)
   bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
   if not is_source_buffer(bufnr) then
      return
   end

   vim.defer_fn(function()
      local client = capabilities.get_client(bufnr)
      if client then
         check_client(client)
         return
      end
      if not config.CONFIG.server.auto_start then
         return
      end
      local path, err, update_with_mason = configured_path()
      if err then
         vim.notify("slang-server.nvim: " .. err, vim.log.levels.ERROR)
      elseif path then
         M.start(path, bufnr, update_with_mason)
      elseif config.CONFIG.mason.install_if_missing then
         pending_buffers[bufnr] = true
         prompt_mason(false)
      end
   end, 100)
end

function M.setup()
   if setup_complete then
      return
   end
   setup_complete = true

   local group = vim.api.nvim_create_augroup("slang-server.manager", { clear = true })
   vim.api.nvim_create_autocmd("FileType", {
      group = group,
      pattern = { "verilog", "systemverilog" },
      callback = function(args)
         M.ensure_buffer(args.buf)
      end,
   })
   vim.api.nvim_create_autocmd("LspAttach", {
      group = group,
      callback = function(args)
         local client = vim.lsp.get_client_by_id(args.data.client_id)
         if client then
            local server_name = client.server_info and client.server_info.name
            if server_name == "slang-server" or client.name == "slang-server" or client.name == "slang_server" then
               check_client(client)
            end
         end
      end,
   })
end

return M
