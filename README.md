# slang-server.nvim

A Neovim client for managed installation and HDL-specific features of [Slang Server](https://github.com/hudson-trading/slang-server).

## Features

Note that it is not necessary to install this plugin in order to use Slang Server.
Neovim supports all standard [LSP](https://microsoft.github.io/language-server-protocol/) commands.
This plugin is for the following features which extend the standard LSP interface.
More information on plugin features can be [found here](https://hudson-trading.github.io/slang-server/hdl/neovim/).

## Requirements

* Neovim 0.10 or newer
* [Nerd Font](https://www.nerdfonts.com/) is recommended

### Plugin dependencies

If installing with lazy.nvim, plugin dependencies are resolved automatically.

* [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
* [mason.nvim](https://github.com/mason-org/mason.nvim) for managed server installation and updates

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

When the first Verilog or SystemVerilog buffer is opened, the plugin uses an already attached `slang-server`, a configured path, `SLANG_SERVER_PATH`, a Mason installation, or a binary on `PATH`, in that order. If none is available, it offers to install the server with Mason. When a server managed by the plugin is from an incompatible major or minor version, it offers to update it with Mason. Explicitly configured and externally managed servers must be updated through their existing installation method.

Use `:SlangServer install` to install the server with Mason, `:SlangServer update` to force a Mason update, and `:SlangServer version` to show the client and server versions.

## Configuration

The default configuration can be found in [config.lua](./lua/slang-server/_core/config.lua). Override options can be defined in the global `vim.g.slang_server_config`, or passed to `opts = {...}` in the lazy.nvim plugin spec.

```lua
require("slang-server").setup({
  server = {
    auto_start = true,
    path = nil,
    args = {},
  },
  mason = {
    install_if_missing = true,
    update_on_mismatch = true,
  },
})
```

Set `server.auto_start = false` to keep startup entirely in another LSP configuration. To let the server identify the plugin version in that case, use `before_init = require("slang-server").before_init` in the external configuration.

The client and server compare major and minor versions during LSP initialization. Patch releases remain compatible; an older major or minor version produces an update warning.
Pre-versioned plugin releases are recognized during LSP initialization and receive an update warning then.

## GitHub Repos

This plugin lives in two repos:

The code is maintained in [Slang Server](https://github.com/hudson-trading/slang-server).  All issues, PRs, etc. should be directed there.

The [slang-server.nvim](https://github.com/hudson-trading/slang-server.nvim) repo is synced from the Neovim client code in the Slang Server repo.  It exists solely as a convenience for plugin managers which require a specific directory structure at the root of the repo.
