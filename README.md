# slang-server.nvim

A Neovim plugin to support non-LSP features of [Slang Server](https://github.com/hudson-trading/slang-server).

## Features

Note that it is not necessary to install this plugin in order to use Slang Server.
Neovim supports all standard [LSP](https://microsoft.github.io/language-server-protocol/) commands.
This plugin is for the following features which extend the standard LSP interface.
More information on plugin features can be [found here](https://hudson-trading.github.io/slang-server/hdl/neovim/).

## Requirements

* Neovim 0.10 or newer
* `slang-server` configured as a Neovim language server
* [Nerd Font](https://www.nerdfonts.com/) is recommended

### Plugin dependencies

If installing with lazy.nvim, plugin dependencies are resolved automatically.

* [nui.nvim](https://github.com/MunifTanjim/nui.nvim)

## Installation

You can use your favorite Neovim plugin manager to download and install the plugin. If you happen to use lazy.nvim you can install the plugin by adding, e.g., `~/.config/nvim/lua/plugins/slang-server.lua`:

```lua
return {
  {
    "hudson-trading/slang-server.nvim",
  },
}
```

The plugin initializes from its filetype plugin when a Verilog or SystemVerilog buffer is opened. To install without a plugin manager, simply clone and place the plugin directory in your Neovim runtimepath.

Configure and install the language server with the Neovim tooling of your choice. For example, `slang-server` is available from [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) as `slang_server` and from [mason.nvim](https://github.com/mason-org/mason.nvim) as `slang-server`. This plugin does not install, configure, or start the language server.

The plugin compares its version with an attached server and warns when the server is too old. The warning suggests updating with your existing package manager and includes `:MasonInstall slang-server` for Mason users.

## Configuration

The default configuration can be found in [config.lua](./lua/slang-server/_core/config.lua). Override options can be defined in the global `vim.g.slang_server_config`, or passed to `opts = {...}` in the lazy.nvim plugin spec.

The plugin checks the server after it attaches, without changing the user's LSP configuration. To additionally advertise the plugin version to the server during initialization, pass the capabilities table produced by your other plugins through `add_client_capabilities`, then use the returned table in your existing LSP configuration:

```lua
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require("slang-server").add_client_capabilities(capabilities)
```

The client and server compare major and minor versions. Patch releases remain compatible; an older major or minor version produces an update warning.

## GitHub Repos

This plugin lives in two repos:

The code is maintained in [Slang Server](https://github.com/hudson-trading/slang-server).  All issues, PRs, etc. should be directed there.

The [slang-server.nvim](https://github.com/hudson-trading/slang-server.nvim) repo is synced from the Neovim client code in the Slang Server repo.  It exists solely as a convenience for plugin managers which require a specific directory structure at the root of the repo.
