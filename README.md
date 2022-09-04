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

## Configuration

You can optionally specify some settings:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-elixir")({
      -- Other formatters to pass to the test command as the formatters are overridden
      -- Can be a function to return a dynamic value.
      extra_formatters = {"ExUnitNotifier"}
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
- [ ] Remove the JSON library dependency by using a simpler format
- [ ] Handle dynamic tests like when you have for a loop that generates tests
- [ ] Show error in line with diagnostics
- [X] Allow specifying extra formatters
