local ok, async = pcall(require, "nio")
if not ok then
  print("use plenary")
  async = require("neotest.async")
end

local Path = require("plenary.path")
local lib = require("neotest.lib")
local base = require("neotest-elixir.base")
local core = require("neotest-elixir.core")
local logger = require("neotest.logging")

---@type neotest.Adapter
local ElixirNeotestAdapter = { name = "neotest-elixir" }

local function get_extra_formatters()
  return { "ExUnit.CLIFormatter" }
end

local function get_mix_task_args()
  return {}
end

local function get_extra_block_identifiers()
  return {}
end
local function get_write_delay()
  return 1000
end

local function get_mix_task()
  return "test"
end

local function get_iex_shell_direction()
  return "horizontal"
end

local function post_process_command(cmd)
  return cmd
end

local function get_relative_path(file_path)
  local mix_root_path = core.mix_root(file_path)
  local root_elems = vim.split(mix_root_path, Path.path.sep)
  local elems = vim.split(file_path, Path.path.sep)
  return table.concat({ unpack(elems, (#root_elems + 1), #elems) }, Path.path.sep)
end

function ElixirNeotestAdapter._generate_id(position, parents)
  if position.dynamic then
    local relative_path = get_relative_path(position.path)
    local line_num = (position.range[1] + 1)
    return (relative_path .. ":" .. line_num)
  else
    return table.concat(
      vim
        .iter({
          position.path,
          vim.tbl_map(function(pos)
            return pos.name
          end, parents),
          position.name,
        })
        :flatten()
        :totable(),
      "::"
    )
  end
end

ElixirNeotestAdapter.root = core.mix_root

function ElixirNeotestAdapter.filter_dir(_, rel_path, _)
  return rel_path == "test"
    or vim.startswith(rel_path, "test/")
    or rel_path == "apps"
    or rel_path:match("^apps/[^/]+$")
    or rel_path:match("^apps/[^/]+/test")
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

local function remove_heredoc_prefix(name)
  local lines = vim.split(name, "\n")
  local common_spaces = 1000
  for _, line in ipairs(lines) do
    local spaces = 0
    for i = 1, line:len() do
      if line:sub(i, i) == " " then
        spaces = spaces + 1
      else
        break
      end
    end

    if spaces < common_spaces then
      common_spaces = spaces
    end
  end

  for i, line in ipairs(lines) do
    lines[i] = line:sub(common_spaces + 1)
  end

  return table.concat(lines, "\n")
end

local function clean_name(name)
  -- Remove quotes
  if vim.startswith(name, '"""') then
    name = name:gsub('^"""', ""):gsub('"""$', "")
  elseif vim.startswith(name, '"') then
    name = name:gsub('^"', ""):gsub('"$', "")
  end

  if vim.startswith(name, "\n  ") then
    name = remove_heredoc_prefix(name:sub(2))
  end

  -- Replace newlines with spaces
  return name:gsub("\n", " "):gsub("\\n", " ")
end

function ElixirNeotestAdapter._build_position(file_path, source, captured_nodes)
  local match_type = get_match_type(captured_nodes)
  if match_type then
    ---@type string
    local name = vim.treesitter.get_node_text(captured_nodes[match_type .. ".name"], source)
    local definition = captured_nodes[match_type .. ".definition"]
    local dynamic = false

    if match_type == "dytest" then
      if vim.startswith(name, "~") then
        name = name:sub(4, #name - 1)
      end
      dynamic = true
    end

    if vim.startswith(name, "doctest ") then
      dynamic = true
    end

    name = clean_name(name)

    return {
      type = match_type_map[match_type],
      path = file_path,
      name = name,
      range = { definition:range() },
      dynamic = dynamic,
    }
  end
end

---@async
---@return neotest.Tree | nil
function ElixirNeotestAdapter.discover_positions(path)
  local test_block_id_list =
    vim.iter({ { "test", "feature", "property" }, get_extra_block_identifiers() }):flatten():totable()
  for index, value in ipairs(test_block_id_list) do
    test_block_id_list[index] = '"' .. value .. '"'
  end
  local test_block_ids = table.concat(test_block_id_list, " ")
  local query = [[
  ;; query
  ;; Describe blocks
  (call
    target: (identifier) @_target (#eq? @_target "describe")
    (arguments . (string (quoted_content) @namespace.name))
    (do_block)
  ) @namespace.definition

  ;; Test blocks (dynamic)
  (call
    target: (identifier) @_target (#any-of? @_target ]] .. test_block_ids .. [[)
    (arguments . [
      (string (interpolation)) ;; String with interpolations
      (identifier) ;; Single variable as name
      (call target: (identifier) @_target2 (#eq? @_target2 "inspect")) ;; Inspect call as name
      (sigil . (sigil_name) @_sigil_name (interpolation)) (#any-of? @_sigil_name "s") ;; Sigil ~s, with interpolations
    ] @dytest.name)
    (do_block)?
  ) @dytest.definition

  ;; Test blocks (static)
  (call
    target: (identifier) @_target (#any-of? @_target ]] .. test_block_ids .. [[)
    (arguments . [
      (string . (quoted_content) @test.name .) ;; Simple string
      (string . (quoted_content) [(escape_sequence) (quoted_content)]+ .) @test.name ;; String with escape sequences
      (sigil . (sigil_name) @_sigil_name . (quoted_content) @test.name .) (#any-of? @_sigil_name "s" "S") ;; Sigil ~s and ~S, no interpolations
    ]
    )
    (do_block)?
  ) @test.definition

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

---@async
---@param args neotest.RunArgs
---@return neotest.RunSpec
function ElixirNeotestAdapter.build_spec(args)
  local position = args.tree:data()

  -- create the results directory and empty file
  local output_dir = async.fn.tempname()
  Path:new(output_dir):mkdir()
  local results_path = output_dir .. "/results"
  local maybe_compile_error_path = output_dir .. "/compile_error"
  logger.debug("result path: " .. results_path)
  core.create_and_clear(results_path)
  core.create_and_clear(maybe_compile_error_path)

  local post_processing_command
  if args.strategy == "iex" then
    local MAGIC_IEX_TERM_ID = 42
    local term = core.get_or_create_iex_term(MAGIC_IEX_TERM_ID, get_iex_shell_direction)
    local seed = core.generate_seed()
    local test_command = core.build_iex_test_command(position, output_dir, seed)
    term:send(test_command, true)
    post_processing_command = core.iex_watch_command(results_path, maybe_compile_error_path, seed)
  else
    local command = core.build_mix_command(position, get_mix_task, get_extra_formatters, get_mix_task_args, args)
    post_processing_command = post_process_command(command)
  end

  local stream_data, stop_stream = lib.files.stream_lines(results_path)
  local write_delay = tostring(get_write_delay())

  return {
    command = post_processing_command,
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
      NEOTEST_PLUGIN_PATH = tostring(core.plugin_path),
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

local function callable_opt(opt)
  if is_callable(opt) then
    return opt
  elseif opt then
    return function()
      return opt
    end
  end
end

setmetatable(ElixirNeotestAdapter, {
  __call = function(_, opts)
    if opts.post_process_command and type(opts.post_process_command) == "function" then
      post_process_command = opts.post_process_command
    end

    local mix_task = callable_opt(opts.mix_task)
    if mix_task then
      get_mix_task = mix_task
    end

    local iex_shell_direction = callable_opt(opts.iex_shell_direction)
    if iex_shell_direction then
      get_iex_shell_direction = iex_shell_direction
    end

    local extra_formatters = callable_opt(opts.extra_formatters)
    if extra_formatters then
      get_extra_formatters = extra_formatters
    end

    local extra_block_identifiers = callable_opt(opts.extra_block_identifiers)
    if extra_block_identifiers then
      get_extra_block_identifiers = extra_block_identifiers
    end

    local args = callable_opt(opts.args)
    if args then
      get_mix_task_args = args
    end

    local write_delay = callable_opt(opts.write_delay)
    if write_delay then
      get_write_delay = write_delay
    end

    return ElixirNeotestAdapter
  end,
})

return ElixirNeotestAdapter
