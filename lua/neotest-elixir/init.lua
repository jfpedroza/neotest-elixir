local Path = require("plenary.path")
local Job = require("plenary.job")
local async = require("neotest.async")
local lib = require("neotest.lib")
local base = require("neotest-elixir.base")
local logger = require("neotest.logging")

---@type neotest.Adapter
local ElixirNeotestAdapter = { name = "neotest-elixir" }

local default_formatters = { "NeotestElixir.Formatter" }

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

local function get_write_delay()
  return 1000
end

---@return "treesitter" | "ex_unit"
local function get_parse_mode()
  return "treesitter"
  -- return "ex_unit"
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

function ElixirNeotestAdapter._generate_id(position)
  local relative_path = get_relative_path(position.path)
  local line_num = (position.range[1] + 1)
  return (relative_path .. ":" .. line_num)
end

local plugin_path = Path.new(script_path()):parent():parent()
local json_encoder = (plugin_path / "neotest_elixir/json_encoder.exs").filename
local exunit_formatter = (plugin_path / "neotest_elixir/neotest_formatter.exs").filename
local exunit_parser = (plugin_path / "neotest_elixir/test_parser.exs").filename

ElixirNeotestAdapter.root = lib.files.match_root_pattern("mix.exs")

function ElixirNeotestAdapter.filter_dir(_, rel_path, _)
  return rel_path == "test" or vim.startswith(rel_path, "test/")
end

function ElixirNeotestAdapter.is_test_file(file_path)
  return base.is_test_file(file_path)
end

local function get_match_type(captured_nodes)
  if captured_nodes["test.name"] then
    return "test"
  end

  if captured_nodes["dytest.name"] then
    return "dytest"
  end

  if captured_nodes["namespace.name"] then
    return "namespace"
  end
end

local match_type_map = {
  test = "test",
  dytest = "test",
  namespace = "namespace",
}

function ElixirNeotestAdapter._build_position(file_path, source, captured_nodes)
  local match_type = get_match_type(captured_nodes)
  if match_type then
    ---@type string
    local name = vim.treesitter.get_node_text(captured_nodes[match_type .. ".name"], source)
    local definition = captured_nodes[match_type .. ".definition"]

    if match_type == "dytest" then
      name = name:gsub('^"', ""):gsub('"$', "")
    end

    return {
      type = match_type_map[match_type],
      path = file_path,
      name = name,
      range = { definition:range() },
    }
  end
end

---@async
---@return neotest.Tree | nil
local function treesitter_discover_positions(path)
  local query = [[
  ;; query
  ;; Describe blocks
  (call
    target: (identifier) @_target (#eq? @_target "describe")
    (arguments . (string (quoted_content) @namespace.name))
    (do_block)
  ) @namespace.definition

  ;; Test blocks (non-dynamic)
  (call
    target: (identifier) @_target (#eq? @_target "test")
    (arguments . (string . (quoted_content) @test.name .))
    (do_block)
  ) @test.definition

  ;; Test blocks (dynamic)
  (call
    target: (identifier) @_target (#eq? @_target "test")
    (arguments . [
      (string (interpolation))
      (identifier)
    ] @dytest.name)
    (do_block)
  ) @dytest.definition

  ;; Doctests
  ;; The word doctest is included in the name to make it easier to notice
  (call 
    target: (identifier) @_target (#eq? @_target "doctest")
  ) @test.name @test.definition
  ]]

  local position_id = 'require("neotest-elixir")._generate_id'
  local build_position = 'require("neotest-elixir")._build_position'
  return lib.treesitter.parse_positions(path, query, { position_id = position_id, build_position = build_position })
end

---@return neotest.Tree | nil
local function ex_unit_discover_posititons(path)
  -- print("Discover", path)

  -- if path:match("player") then
  local positions = {}
  local status_ok, result = pcall(function()
    local job_id = vim.fn.jobstart({ "mix", "run", "--no-start", "-r", json_encoder, exunit_parser, path }, {
      env = {
        MIX_ENV = "test",
      },
      stdout_buffered = true,
      on_stdout = function(_, data)
        if not data then
          return
        end

        for _, line in ipairs(data) do
          -- print("Line", line)
          if line ~= "" then
            table.insert(positions, vim.json.decode(line))
          end
        end
      end,
      on_exit = function() end,
    })

    if job_id > 0 then
      vim.fn.jobwait({ job_id }, 3000)
    end
  end)

  if not status_ok then
    print("Stauts not OK", result)
  end

  local position_id = 'require("neotest-elixir")._generate_id'
  return lib.positions.parse_tree(positions, { position_id = position_id })
  -- print("Got here", path)
  -- else
  --   return treesitter_discover_positions(path)
  -- end
end

---@async
---@return neotest.Tree | nil
function ElixirNeotestAdapter.discover_positions(path)
  local parse_mode = get_parse_mode()

  if parse_mode == "treesitter" then
    return treesitter_discover_positions(path)
  elseif parse_mode == "ex_unit" then
    return ex_unit_discover_posititons(path)
  end
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

  local write_delay = tostring(get_write_delay())

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
      NEOTEST_WRITE_DELAY = write_delay,
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

    if is_callable(opts.write_delay) then
      get_write_delay = opts.write_delay
    elseif opts.write_delay then
      get_write_delay = function()
        return opts.write_delay
      end
    end

    return ElixirNeotestAdapter
  end,
})

return ElixirNeotestAdapter
