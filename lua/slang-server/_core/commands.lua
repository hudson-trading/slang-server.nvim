local M = {}
local setup_complete = false

function M.setup()
   if setup_complete then
      return
   end
   setup_complete = true

   local command = "SlangServer"
   local subcommands = {}
   subcommands = vim.tbl_deep_extend("error", subcommands, require("slang-server._commands.manage"))
   subcommands = vim.tbl_deep_extend("error", subcommands, require("slang-server._commands.setTopLevel"))
   subcommands = vim.tbl_deep_extend("error", subcommands, require("slang-server._commands.setBuildFile"))
   subcommands = vim.tbl_deep_extend("error", subcommands, require("slang-server._commands.hierarchy"))
   subcommands = vim.tbl_deep_extend("error", subcommands, require("slang-server._commands.openWaveform"))
   subcommands = vim.tbl_deep_extend("error", subcommands, require("slang-server._commands.addToWaves"))

   vim.api.nvim_create_user_command(command, function(opts)
      local subcommand_key = opts.fargs[1]
      local args = #opts.fargs > 1 and vim.list_slice(opts.fargs, 2, #opts.fargs) or {}
      local subcommand = subcommands[subcommand_key]
      if not subcommand then
         vim.notify(command, vim.log.levels.ERROR)
         return
      end
      subcommand.impl(args, opts)
   end, {
      nargs = "+",
      desc = "SlangServer",
      complete = function(arg_lead, cmdline, _)
         local subcmd_key, subcmd_arg_lead = cmdline:match("^" .. command .. "%s(%S+)%s(.*)$")
         if subcmd_key and subcmd_arg_lead and subcommands[subcmd_key] and subcommands[subcmd_key].complete then
            return subcommands[subcmd_key].complete(subcmd_arg_lead)
         end

         if cmdline:find("^" .. command .. "%s+%w*$") then
            return vim.iter(vim.tbl_keys(subcommands))
               :filter(function(key)
                  return key:find("^" .. arg_lead) ~= nil
               end)
               :totable()
         end
      end,
   })
end

return M
