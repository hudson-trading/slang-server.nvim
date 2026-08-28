local slang_server = require("slang-server")
local version = require("slang-server.version")

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

   it("adds the plugin identity without replacing other client capabilities", function()
      local result = slang_server.add_client_capabilities({
         workspace = { configuration = true },
         experimental = { otherClientFeature = true },
      })

      assert.are.same({ configuration = true }, result.workspace)
      assert.is_true(result.experimental.otherClientFeature)
      assert.are.same(
         { name = version.NAME, version = version.VERSION },
         result.experimental.slangClient
      )
   end)

   it("only notifies once and suggests Mason without invoking it", function()
      local client = { id = 900001, server_info = { version = "0.0.0" } }
      local old_notify = vim.notify
      local messages = {}
      vim.notify = function(message)
         messages[#messages + 1] = message
      end

      version.notify_if_incompatible(client)
      version.notify_if_incompatible(client)
      vim.notify = old_notify

      assert.are.equal(1, #messages)
      assert.is_not_nil(messages[1]:find(":MasonInstall slang-server", 1, true))
   end)
end)
