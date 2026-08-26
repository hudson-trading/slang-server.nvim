local M = {}

function M.path()
   local settings_ok, settings = pcall(require, "mason.settings")
   if settings_ok then
      local executable = vim.fn.has("win32") == 1 and "slang-server.exe" or "slang-server"
      local path = settings.current.install_root_dir .. package.config:sub(1, 1) .. "bin" .. package.config:sub(1, 1) .. executable
      if vim.fn.executable(path) == 1 then
         return path
      end
   end

   return nil
end

---@param force boolean
---@param callback fun(path: string?, err: string?)
function M.install(force, callback)
   local ok, registry = pcall(require, "mason-registry")
   if not ok then
      callback(nil, "mason.nvim is not available")
      return
   end

   local function begin_install()
      if not registry.has_package("slang-server") then
         callback(nil, "Mason does not know about slang-server; run :MasonUpdate and try again")
         return
      end

      local mason_package = registry.get_package("slang-server")
      if mason_package:is_installed() and not force then
         callback(M.path(), nil)
         return
      end

      local finished = false
      local function complete(path, err)
         if finished then
            return
         end
         finished = true
         vim.schedule(function()
            callback(path, err)
         end)
      end

      local listen = mason_package.once or mason_package.on
      listen(mason_package, "install:success", function()
         complete(M.path(), nil)
      end)
      listen(mason_package, "install:failed", function()
         complete(nil, "Mason failed to install slang-server")
      end)

      if mason_package:is_installing() then
         return
      end
      local ok, install_err = pcall(mason_package.install, mason_package, { force = force })
      if not ok then
         complete(nil, tostring(install_err))
      end
   end

   if force then
      registry.refresh(begin_install)
   else
      begin_install()
   end
end

return M
