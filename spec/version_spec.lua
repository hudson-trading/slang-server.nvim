local manager = require("slang-server._core.manager")
local mason = require("slang-server._core.mason")
local version = require("slang-server.version")
local capabilities = require("slang-server._lsp.capabilities")
local config = require("slang-server._core.config")

describe("version compatibility", function()
   it("keeps the rockspec version in sync", function()
      local rockspec = io.open("slang-server.nvim-" .. version.VERSION .. "-1.rockspec", "r")
      assert.is_not_nil(rockspec)
      local contents = rockspec:read("*a")
      rockspec:close()
      assert.is_not_nil(contents:find('version = "' .. version.VERSION .. '-1"', 1, true))
      assert.is_not_nil(contents:find('tag = "v' .. version.VERSION .. '"', 1, true))
   end)

   it("parses release and build versions", function()
      assert.are.same({ 0, 2, 10 }, { version.parse("v0.2.10+abcdef") })
      assert.are.same({ 1, 0, 0 }, { version.parse("1.0.0") })
      assert.is_nil(version.parse("development"))
   end)

   it("compares only major and minor for client compatibility", function()
      assert.is_true(version.major_minor_at_least("0.2.0", "0.2.17"))
      assert.is_false(version.major_minor_at_least("0.1.99", "0.2.0"))
   end)

   it("advertises the plugin identity during initialization", function()
      local params = { capabilities = {} }
      manager.before_init(params)
      assert.are.same(
         { name = version.NAME, version = version.VERSION },
         params.capabilities.experimental.slangClient
      )
   end)

   it("rejects servers from an older major or minor version", function()
      assert.is_true(capabilities.version_compatible({ server_info = { version = version.VERSION } }))
      assert.is_false(capabilities.version_compatible({ server_info = { version = "0.0.0" } }))
   end)
end)

describe("Mason integration", function()
   it("treats servers discovered on PATH as externally managed", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_call(bufnr, function()
         vim.cmd("noautocmd setlocal filetype=systemverilog")
      end)

      local old_get_client = capabilities.get_client
      local old_mason_path = mason.path
      local old_exepath = vim.fn.exepath
      local old_start = manager.start
      local old_configured_path = config.CONFIG.server.path
      local old_env_path = vim.env.SLANG_SERVER_PATH
      local started

      capabilities.get_client = function()
         return nil
      end
      mason.path = function()
         return nil
      end
      vim.fn.exepath = function(name)
         assert.are.equal("slang-server", name)
         return "/usr/bin/slang-server"
      end
      manager.start = function(path, start_bufnr, update_with_mason)
         started = { path, start_bufnr, update_with_mason }
      end
      config.CONFIG.server.path = nil
      vim.env.SLANG_SERVER_PATH = nil

      manager.ensure_buffer(bufnr)
      local completed = vim.wait(1000, function()
         return started ~= nil
      end)

      capabilities.get_client = old_get_client
      mason.path = old_mason_path
      vim.fn.exepath = old_exepath
      manager.start = old_start
      config.CONFIG.server.path = old_configured_path
      vim.env.SLANG_SERVER_PATH = old_env_path
      vim.api.nvim_buf_delete(bufnr, { force = true })

      assert.is_true(completed)
      assert.are.same({ "/usr/bin/slang-server", bufnr, false }, started)
   end)

   it("requests a forced install and reports its path", function()
      local listeners = {}
      local install_options
      local fake_package = {
         is_installed = function()
            return true
         end,
         is_installing = function()
            return false
         end,
         on = function(_, event, callback)
            listeners[event] = callback
         end,
         install = function(_, options)
            install_options = options
            listeners["install:success"]()
         end,
      }
      local old_registry = package.loaded["mason-registry"]
      package.loaded["mason-registry"] = {
         refresh = function(callback)
            callback()
         end,
         has_package = function()
            return true
         end,
         get_package = function()
            return fake_package
         end,
      }
      local old_path = mason.path
      mason.path = function()
         return "/mason/bin/slang-server"
      end

      local installed_path
      mason.install(true, function(path)
         installed_path = path
      end)
      assert.is_true(vim.wait(1000, function()
         return installed_path ~= nil
      end))

      mason.path = old_path
      package.loaded["mason-registry"] = old_registry
      assert.is_true(install_options.force)
      assert.are.equal("/mason/bin/slang-server", installed_path)
   end)

   it("keeps managed ownership across buffer detaches and restarts every client", function()
      manager.setup()

      local buffers = { vim.api.nvim_create_buf(false, true), vim.api.nvim_create_buf(false, true) }
      for _, bufnr in ipairs(buffers) do
         vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("noautocmd setlocal filetype=systemverilog")
         end)
      end

      local clients = {
         { id = 900001, name = "slang-server", server_info = { name = "slang-server", version = "0.0.0" } },
         { id = 900002, name = "slang-server", server_info = { name = "slang-server", version = "0.0.0" } },
      }
      local stopped = {}
      for _, client in ipairs(clients) do
         client.stop = function(self, force)
            assert.are.equal(client, self)
            assert.is_true(force)
            stopped[self.id] = true
         end
      end

      local old_get_client = capabilities.get_client
      local old_lsp_start = vim.lsp.start
      local old_get_client_by_id = vim.lsp.get_client_by_id
      local old_get_buffers = vim.lsp.get_buffers_by_client_id
      local old_select = vim.ui.select
      local old_notify = vim.notify
      local old_install = mason.install
      local next_client = 1
      local exit_callbacks = {}
      local select_callback

      capabilities.get_client = function()
         return nil
      end
      vim.lsp.start = function(start_config)
         local client = clients[next_client]
         exit_callbacks[client.id] = start_config.on_exit
         start_config.on_init(client)
         next_client = next_client + 1
      end
      vim.lsp.get_client_by_id = function(client_id)
         for _, client in ipairs(clients) do
            if client.id == client_id then
               return client
            end
         end
      end
      vim.lsp.get_buffers_by_client_id = function()
         return {}
      end
      vim.ui.select = function(_, _, callback)
         select_callback = callback
      end
      vim.notify = function() end
      mason.install = function(force, callback)
         assert.is_true(force)
         callback("/mason/bin/slang-server", nil)
      end

      manager.start("/mason/bin/slang-server", buffers[1], true)
      manager.start("/mason/bin/slang-server", buffers[2], true)
      vim.api.nvim_exec_autocmds("LspDetach", { buffer = buffers[1], data = { client_id = clients[1].id } })
      for index, client in ipairs(clients) do
         vim.api.nvim_exec_autocmds("LspAttach", { buffer = buffers[index], data = { client_id = client.id } })
      end
      assert.is_not_nil(select_callback)
      select_callback("Update")
      assert.is_true(stopped[clients[1].id])
      assert.is_true(stopped[clients[2].id])

      capabilities.get_client = old_get_client
      vim.lsp.start = old_lsp_start
      vim.lsp.get_client_by_id = old_get_client_by_id
      vim.lsp.get_buffers_by_client_id = old_get_buffers
      vim.ui.select = old_select
      vim.notify = old_notify
      mason.install = old_install
      for index, client in ipairs(clients) do
         exit_callbacks[client.id](0, 0, client.id)
         vim.api.nvim_buf_delete(buffers[index], { force = true })
      end
   end)

   it("does not offer Mason updates for explicitly configured clients", function()
      manager.setup()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_call(bufnr, function()
         vim.cmd("noautocmd setlocal filetype=systemverilog")
      end)
      local client = {
         id = 900003,
         name = "slang-server",
         server_info = { name = "slang-server", version = "0.0.0" },
      }

      local old_get_client = capabilities.get_client
      local old_lsp_start = vim.lsp.start
      local old_get_client_by_id = vim.lsp.get_client_by_id
      local old_select = vim.ui.select
      local old_notify = vim.notify
      local exit_callback
      local selected = false

      capabilities.get_client = function()
         return nil
      end
      vim.lsp.start = function(start_config)
         exit_callback = start_config.on_exit
         start_config.on_init(client)
      end
      vim.lsp.get_client_by_id = function()
         return client
      end
      vim.ui.select = function()
         selected = true
      end
      vim.notify = function() end

      manager.start("/configured/slang-server", bufnr, false)
      vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = client.id } })
      assert.is_false(selected)

      capabilities.get_client = old_get_client
      vim.lsp.start = old_lsp_start
      vim.lsp.get_client_by_id = old_get_client_by_id
      vim.ui.select = old_select
      vim.notify = old_notify
      exit_callback(0, 0, client.id)
      vim.api.nvim_buf_delete(bufnr, { force = true })
   end)

   it("warns only once per client across buffer detaches", function()
      local client = { id = 900004, server_info = { version = "0.0.0" } }
      local old_notify = vim.notify
      local warnings = 0
      vim.notify = function()
         warnings = warnings + 1
      end

      capabilities.notify_version(client)
      vim.api.nvim_exec_autocmds("LspDetach", { data = { client_id = client.id } })
      capabilities.notify_version(client)
      assert.are.equal(1, warnings)

      vim.notify = old_notify
   end)
end)
