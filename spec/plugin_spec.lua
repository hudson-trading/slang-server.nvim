-- wait for hierarchy to finish resolving
---@param buf_name string
local function wait_on(buf_name)
   local lines

   local buf = nil
   local win = nil
   for _, candidate_win in ipairs(vim.api.nvim_list_wins()) do
      local this_buf = vim.api.nvim_win_get_buf(candidate_win)
      local this_name = vim.api.nvim_buf_get_name(this_buf)

      if string.find(this_name, buf_name, 1, true) then
         buf = this_buf
         win = candidate_win
         break
      end
   end
   assert(buf)

   local success, _ = vim.wait(5000, function()
      lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      if #lines < 1 then
         return false
      end
      for _, line in ipairs(lines) do
         if string.find(line, "Loading ") then
            return false
         end
      end
      return true
   end)
   assert(success, lines)

   return lines, win
end

local function find_line(lines, text)
   for index, line in ipairs(lines) do
      if string.find(line, text, 1, true) then
         return index
      end
   end
   error("Could not find line containing " .. text)
end

local function press_key(win, line, key)
   vim.api.nvim_set_current_win(win)
   vim.api.nvim_win_set_cursor(win, { line, 0 })
   vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "mx", false)
end

---@param fn fun()
---@return string[]
local function capture_notifications(fn)
   local old_notify = vim.notify
   local messages = {}
   vim.notify = function(msg, ...)
      messages[#messages + 1] = msg
   end

   local ok, err = pcall(fn)
   vim.notify = old_notify
   assert(ok, err)
   return messages
end

describe("SlangServer", function()
   -- load test SV
   vim.cmd("edit tests/foo.sv")
   vim.cmd("set filetype=systemverilog")
   local source_buf = vim.api.nvim_get_current_buf()
   -- start slang-server
   local server_bin = os.getenv("SLANG_SERVER_BIN") or "../../build/bin/slang-server"
   local client = vim.lsp.start({
      name = "slang-server",
      cmd = { server_bin },
      filetypes = { "systemverilog" },
      root_dir = vim.uv.cwd(),
   })
   assert(client)
   local function execute_server_command(command, arguments)
      local done = false
      local response
      local request_error
      vim.lsp.get_client_by_id(client):request(
         "workspace/executeCommand",
         { command = command, arguments = arguments },
         function(err, result)
            request_error = err
            response = result
            done = true
         end,
         source_buf
      )
      assert(vim.wait(5000, function()
         return done
      end))
      assert.is_nil(request_error)
      return response
   end
   -- wait for client to attach to this buffer
   local success, _ = vim.wait(5000, function()
      return #vim.lsp.get_clients() > 0
   end)
   assert(success)
   -- load the plugin, not sure if this is the canonical way to do this from busted
   vim.cmd("luafile ftplugin/systemverilog.lua")
   vim.cmd("luafile lua/slang-server/init.lua")
   -- compile design
   vim.cmd("SlangServer setTopLevel")

   it("Generic quick pick dispatches its selected value", function()
      local client_commands = require("slang-server._lsp.clientCommands")
      local original_select = vim.ui.select
      local original_execute = client_commands.executeServerCommand
      local command
      local selected

      local ok, err = pcall(function()
         client_commands.executeServerCommand = function(selected_command, value)
            command = selected_command
            selected = value
         end
         vim.ui.select = function(items, options, on_choice)
            assert.are.same("Pick one", options.prompt)
            assert.are.same("second (current)", options.format_item(items[2]))
            on_choice(items[2])
         end
         vim.lsp.commands["slang.quickPick"]({
            arguments = {
               {
                  placeholder = "Pick one",
                  items = {
                     { label = "first", value = 1 },
                     { label = "second", description = "(current)", value = 2 },
                  },
                  onSelectCommand = "test.callback",
               },
            },
         }, { bufnr = 0 })
      end)
      vim.ui.select = original_select
      client_commands.executeServerCommand = original_execute

      assert(ok, err)
      assert.are.same("test.callback", command)
      assert.are.same(2, selected)
   end)

   it("Active instance notifications reveal an open hierarchy", function()
      local client_commands = require("slang-server._lsp.clientCommands")
      local navigation = require("slang-server.navigation")
      local hierarchy = require("slang-server.navigation/hierarchy")
      local original_open = hierarchy.open_remainder
      local original_state = navigation.state.open
      local revealed

      local ok, err = pcall(function()
         hierarchy.open_remainder = function(parent, root, path, from_cell)
            revealed = { parent, root, path, from_cell }
         end

         navigation.state.open = false
         client_commands.activeInstanceChanged(nil, { hierPath = "top.hidden" })
         assert.is_nil(revealed)

         navigation.state.open = true
         client_commands.activeInstanceChanged(nil, { hierPath = "top.visible" })
         assert.are.same({ nil, true, "top.visible", false }, revealed)
      end)
      hierarchy.open_remainder = original_open
      navigation.state.open = original_state

      assert(ok, err)
   end)

   it("Single-instance code lenses reveal an open hierarchy", function()
      local client_commands = require("slang-server._lsp.clientCommands")
      local original_reveal = client_commands.revealInHierarchy
      local shown

      local ok, err = pcall(function()
         client_commands.revealInHierarchy = function(params)
            shown = params
         end
         vim.lsp.commands["slang.showInHierarchy"]({
            arguments = { { hierPath = "top.only" } },
         })
      end)
      client_commands.revealInHierarchy = original_reveal

      assert(ok, err)
      assert.are.same({ hierPath = "top.only" }, shown)
   end)

   it("Searches hierarchy members through the server API", function()
      local result
      require("slang-server").search_hierarchy("the_sub", function(resp)
         result = resp
      end)

      assert(vim.wait(5000, function()
         return result ~= nil
      end))
      assert.are.same(4, result.totalResults)
      assert.is_true(#result.matches <= 100)
      assert.is_true(vim.iter(result.matches):any(function(item)
         return item.path == "foo.gen_loop[2].the_sub"
      end))
   end)

   it("Hierarchy no args", function()
      vim.cmd("SlangServer hierarchy")
      local lines = wait_on("Slang-server: Hierarchy")
      local expected = [=[
   foo foo]=]
      assert.are.same(expected, table.concat(lines, "\n"))
      lines = wait_on("Slang-server: Cells")
      expected = [=[
  foo (1)
   └╴foo
  sub (4)]=]
      assert.are.same(expected, table.concat(lines, "\n"))
      vim.api.nvim_buf_delete(0, { force = true })
   end)

   it("Explicit commands use the source buffer when focus is in the hierarchy panel", function()
      vim.cmd("SlangServer hierarchy")
      wait_on("Slang-server: Hierarchy")

      local messages = capture_notifications(function()
         vim.cmd("SlangServer setTopLevel tests/foo.sv")
      end)
      for _, msg in ipairs(messages) do
         assert.is_nil(string.find(msg, "no slang-server LSP client attached", 1, true))
      end

      vim.api.nvim_buf_delete(0, { force = true })
   end)

   it("Context-sensitive commands require source buffer focus", function()
      vim.cmd("SlangServer hierarchy")
      wait_on("Slang-server: Hierarchy")

      local messages = capture_notifications(function()
         vim.cmd("SlangServer setTopLevel")
         vim.cmd("SlangServer addToWaves")
      end)

      assert.are.same({
         "slang-server: setTopLevel without a file must be run from a buffer with an attached slang-server LSP client.",
         "slang-server: addToWaves must be run from a buffer with an attached slang-server LSP client.",
      }, messages)

      for _, msg in ipairs(messages) do
         assert.is_nil(string.find(msg, "Please upgrade slang-server", 1, true))
      end

      vim.api.nvim_buf_delete(0, { force = true })
   end)

   it("Hierarchy with scope arg", function()
      vim.cmd("SlangServer hierarchy foo.gen_loop[2].the_sub")
      local lines = wait_on("Slang-server: Hierarchy")
      local expected = [=[
   foo foo
   └╴ 󰅩 gen_loop
     ├╴ 󰅩 [0]
     ├╴ 󰅩 [1]
     ├╴ 󰅩 [2]
       ├╴   i integer
       └╴  the_sub sub
         └╴   param int
     └╴ 󰅩 [3]]=]
      assert.are.same(expected, table.concat(lines, "\n"))
      lines = wait_on("Slang-server: Cells")
      expected = [=[
  foo (1)
   └╴foo
  sub (4)]=]
      assert.are.same(expected, table.concat(lines, "\n"))
      vim.api.nvim_buf_delete(0, { force = true })
   end)

   it("Cell selections activate instances", function()
      execute_server_command("slang.setTopLevel", { vim.api.nvim_buf_get_name(source_buf) })
      vim.cmd("SlangServer hierarchy")

      local lines, cells_win = wait_on("Slang-server: Cells")
      press_key(cells_win, find_line(lines, "sub (4)"), "<Space>")
      lines, cells_win = wait_on("Slang-server: Cells")
      local target = "foo.gen_loop[2].the_sub"
      press_key(cells_win, find_line(lines, target), "<CR>")

      local active = execute_server_command("slang.getActiveInstance", { "sub" })
      assert.are.same(target, active.instPath)

      local _, hierarchy_win = wait_on("Slang-server: Hierarchy")
      vim.api.nvim_set_current_win(hierarchy_win)
      vim.api.nvim_buf_delete(0, { force = true })
   end)

   it("Hierarchy selections activate instances", function()
      execute_server_command("slang.setTopLevel", { vim.api.nvim_buf_get_name(source_buf) })
      local target = "foo.gen_loop[3].the_sub"
      vim.cmd("SlangServer hierarchy " .. target)

      local lines, hierarchy_win = wait_on("Slang-server: Hierarchy")
      press_key(hierarchy_win, find_line(lines, "the_sub sub"), "<CR>")

      local active = execute_server_command("slang.getActiveInstance", { "sub" })
      assert.are.same(target, active.instPath)
      vim.api.nvim_buf_delete(0, { force = true })
   end)
end)

-- TODO (tests)
-- * cone tracing
-- * WCP
