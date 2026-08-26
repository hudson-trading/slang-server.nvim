local M = {}

---@type slang-server.ui.Subcommand
M.install = {
   impl = function()
      require("slang-server._core.manager").install()
   end,
}

---@type slang-server.ui.Subcommand
M.update = {
   impl = function()
      require("slang-server._core.manager").update()
   end,
}

---@type slang-server.ui.Subcommand
M.version = {
   impl = function()
      local version_info = require("slang-server.version")
      local capabilities = require("slang-server._lsp.capabilities")
      local client = capabilities.get_client(capabilities.get_source_context())
      local server_version = client and client.server_info and client.server_info.version or "not attached"
      vim.notify(
         string.format("%s %s, slang-server %s", version_info.NAME, version_info.VERSION, vim.trim(server_version)),
         vim.log.levels.INFO
      )
   end,
}

return M
