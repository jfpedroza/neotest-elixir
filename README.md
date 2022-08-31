# neotest-elixir

[WIP] Neotest adapter for Elixir

Status: The adapter is currently working, you can execute the different types (single test, file, etc.) and see the result and the output.

## Installation

Using packer:

```lua
use({
  'nvim-neotest/neotest',
  requires = {
    ...,
    'nvim-neotest/neotest-elixir',
  }
  config = function()
    require('neotest').setup({
      ...,
      adapters = {
        require('neotest-elixir'),
      }
    })
  end
})
```

## TODO

- [X] Store output in temp files directly from the ExUnit formatter
- [X] Enable colors
- [ ] Remove the JSON library dependency by using a simpler format
- [ ] Handle dynamic tests like when you have for a loop that generates tests
- [ ] Show error in line with diagnostics
- [ ] Allow other formatters (I use ExUnitNotifier, and it doesn't work because I override the formatters)

