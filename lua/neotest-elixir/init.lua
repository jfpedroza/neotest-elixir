local lib = require("neotest.lib")
local base = require("neotest-elixir.base")

---@type neotest.Adapter
local ElixirNeotestAdapter = { name = "neotest-elixir" }

ElixirNeotestAdapter.root = lib.files.match_root_pattern("mix.exs")

function ElixirNeotestAdapter.is_test_file(file_path)
  return base.is_test_file(file_path)
end

function ElixirNeotestAdapter.discover_positions(path)
  local query = [[
  ;; Describe blocks
  (call
    target: (identifier) @_target (#eq? @_target "describe")
    (arguments ((string (quoted_content) @namespace.name)))
    (do_block)
  ) @namespace.definition

  ;; Test blocks
  (call
    target: (identifier) @_target (#eq? @_target "test")
    (arguments ((string (quoted_content) @test.name)))
    (do_block)
  ) @test.definition
  ]]

  return lib.treesitter.parse_positions(path, query, { nested_namespaces = false })
end

function ElixirNeotestAdapter.build_spec(args)
  print(vim.inspect(args))
end

function ElixirNeotestAdapter.results(spec, result, tree)
  print(vim.inspect(spec))
  print(vim.inspect(result))
  print(vim.inspect(tree))
end

return ElixirNeotestAdapter
