# neotest-elixir

[WIP] Neotest adapter for Elixir

Status: The adapter is currently working, you can execute the different types (single test, file, etc.) and see the result and the output.

## Installation

Using packer:

```lua
use({
  "nvim-neotest/neotest",
  requires = {
    ...,
    "nvim-neotest/neotest-elixir",
  }
  config = function()
    require("neotest").setup({
      ...,
      adapters = {
        require("neotest-elixir"),
      }
    })
  end
})
```

## Caveats

Currently, the adapter requires either Jason or Poison to be available in the project

## Configuration

You can optionally specify some settings:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-elixir")({
      -- Other formatters to pass to the test command as the formatters are overridden
      -- Can be a function to return a dynamic value.
      -- Default: {"ExUnit.CLIFormatter"}
      extra_formatters = {"ExUnit.CLIFormatter", "ExUnitNotifier"}
      -- Can be Jason or Poison, default: Jason
      json_module = "Jason"
    }),
  }
})
```

`extra_args` are also supported, so you can use them to specify other arguments to `mix test`:

```lua
require("neotest").run.run({vim.fn.expand("%"), extra_args = {"--formatter", "ExUnitNotifier", "--timeout", "60"}}))
```

## TODO

- [X] Store output in temp files directly from the ExUnit formatter
- [X] Enable colors
- [ ] Support projects without a JSON library in the dependencies
- [ ] Handle dynamic tests like when you have for a loop that generates tests
- [ ] Show error in line with diagnostics
- [X] Allow specifying extra formatters
