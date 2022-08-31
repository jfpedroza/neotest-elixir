local Path = require("plenary.path")
local async = require("neotest.async")
local lib = require("neotest.lib")
local base = require("neotest-elixir.base")

---@type neotest.Adapter
local ElixirNeotestAdapter = { name = "neotest-elixir" }

---@param position neotest.Position
---@return string[]
local function get_args(position)
  if position.type == "dir" then
    local root = ElixirNeotestAdapter.root(position.path)
    local path = Path:new(position.path)
    local relative = path:make_relative(root)

    if relative == "." then
      return {}
    else
      return { relative }
    end
  elseif position.type == "file" then
    return { position.path }
  else
    local line = position.range[1] + 1
    return { position.path .. ":" .. line }
  end
end

local function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end

local exunit_formatter = (Path.new(script_path()):parent():parent() / "neotest_elixir/neotest_formatter.exs").filename

ElixirNeotestAdapter.root = lib.files.match_root_pattern("mix.exs")

function ElixirNeotestAdapter.is_test_file(file_path)
  return base.is_test_file(file_path)
end

---@async
---@return neotest.Tree | nil
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

---@async
---@param args neotest.RunArgs
---@return neotest.RunSpec
function ElixirNeotestAdapter.build_spec(args)
  local position = args.tree:data()
  local command = vim.list_extend(
    { "elixir", "-r", exunit_formatter, "-S", "mix", "test", "--formatter", "NeotestElixirFormatter" },
    get_args(position)
  )
  local output_dir = async.fn.tempname()

  return {
    command = command,
    env = {
      NEOTEST_OUTPUT_DIR = output_dir,
    },
  }
end

---@async
---@param result neotest.StrategyResult
---@return neotest.Result[]
function ElixirNeotestAdapter.results(_, result)
  local data = lib.files.read_lines(result.output)
  local results = {}

  for _, line in ipairs(data) do
    local ok, decoded_result = pcall(vim.json.decode, line, { luanil = { object = true } })
    if ok then
      results[decoded_result.id] = {
        status = decoded_result.status,
        output = decoded_result.output,
      }
    end
  end

  return results
end

return ElixirNeotestAdapter
