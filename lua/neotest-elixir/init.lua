local Path = require("plenary.path")
local async = require("neotest.async")
local lib = require("neotest.lib")
local base = require("neotest-elixir.base")
local logger = require("neotest.logging")

---@type neotest.Adapter
local ElixirNeotestAdapter = { name = "neotest-elixir" }

local default_formatters = { "NeotestElixirFormatter" }

local function get_extra_formatters()
  return { "ExUnit.CLIFormatter" }
end

local function get_formatters()
  -- tables need to be copied by value
  local formatters = { unpack(default_formatters) }
  vim.list_extend(formatters, get_extra_formatters())

  local result = {}
  for _, formatter in ipairs(formatters) do
    table.insert(result, "--formatter")
    table.insert(result, formatter)
  end

  return result
end

local function get_args(_)
  return {}
end

---@param position neotest.Position
---@return string[]
local function get_args_from_position(position)
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

local function mix_root(file_path)
  return lib.files.match_root_pattern("mix.exs")(file_path)
end

local function get_relative_path(file_path)
  local mix_root_path = mix_root(file_path)
  local root_elems = vim.split(mix_root_path, Path.path.sep)
  local elems = vim.split(file_path, Path.path.sep)
  return table.concat({ unpack(elems, (#root_elems + 1), #elems) }, Path.path.sep)
end

local function generate_id(position)
  local relative_path = get_relative_path(position.path)
  local line_num = (position.range[1] + 1)
  return (relative_path .. ":" .. line_num)
end

local json_encoder = (Path.new(script_path()):parent():parent() / "neotest_elixir/json_encoder.exs").filename
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

  return lib.treesitter.parse_positions(path, query, { nested_namespaces = false, position_id = generate_id })
end

---@async
---@param args neotest.RunArgs
---@return neotest.RunSpec
function ElixirNeotestAdapter.build_spec(args)
  local position = args.tree:data()
  local command = vim.tbl_flatten({
    {
      "elixir",
      "-r",
      json_encoder,
      "-r",
      exunit_formatter,
      "-S",
      "mix",
      "test",
    },
    get_formatters(),
    get_args(position),
    args.extra_args or {},
    get_args_from_position(position),
  })

  local output_dir = async.fn.tempname()
  Path:new(output_dir):mkdir()
  local results_path = output_dir .. "/results"
  logger.debug("result path: " .. results_path)
  local x = io.open(results_path, "w")
  x:write("")
  x:close()

  local stream_data, stop_stream = lib.files.stream_lines(results_path)
  local json_module = ElixirNeotestAdapter.json_module or "Jason"

  return {
    command = command,
    context = {
      position = position,
      results_path = results_path,
      stop_stream = stop_stream,
    },
    stream = function()
      return function()
        local lines = stream_data()
        local results = {}
        for _, line in ipairs(lines) do
          local decoded_result = vim.json.decode(line, { luanil = { object = true } })
          local earlier_result = results[decoded_result.id]
          if earlier_result == nil or earlier_result.status ~= "failed" then
            results[decoded_result.id] = {
              status = decoded_result.status,
              output = decoded_result.output,
              errors = decoded_result.errors,
            }
          end
        end
        return results
      end
    end,
    env = {
      NEOTEST_OUTPUT_DIR = output_dir,
      NEOTEST_JSON_MODULE = json_module,
    },
  }
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@return neotest.Result[]
function ElixirNeotestAdapter.results(spec, result)
  spec.context.stop_stream()
  local results = {}
  if result.code == 0 or result.code == 2 then
    local data = lib.files.read_lines(spec.context.results_path)

    for _, line in ipairs(data) do
      local decoded_result = vim.json.decode(line, { luanil = { object = true } })
      local earlier_result = results[decoded_result.id]
      if earlier_result == nil or earlier_result.status ~= "failed" then
        results[decoded_result.id] = {
          status = decoded_result.status,
          output = decoded_result.output,
          errors = decoded_result.errors,
        }
      end
    end
  else
    results[spec.context.position.id] = {
      status = "failed",
      output = result.output,
    }
  end

  return results
end

local is_callable = function(obj)
  return type(obj) == "function" or (type(obj) == "table" and obj.__call)
end

setmetatable(ElixirNeotestAdapter, {
  __call = function(_, opts)
    if is_callable(opts.extra_formatters) then
      get_extra_formatters = opts.extra_formatters
    elseif opts.extra_formatters then
      get_extra_formatters = function()
        return opts.extra_formatters
      end
    end

    if is_callable(opts.args) then
      get_args = opts.args
    elseif opts.args then
      get_args = function()
        return opts.args
      end
    end

    ElixirNeotestAdapter.json_module = opts.json_module

    return ElixirNeotestAdapter
  end,
})

return ElixirNeotestAdapter
