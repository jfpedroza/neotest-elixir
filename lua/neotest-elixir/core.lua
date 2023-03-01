local lib = require("neotest.lib")
local Path = require("plenary.path")

local M = {}

local function relative_to_cwd(path)
  local root = lib.files.match_root_pattern("mix.exs")(path)
  return Path:new(path):make_relative(root)
end

-- Build the command to send to the IEx shell for running the test
function M.build_iex_test_command(position, output_dir, seed, relative_to)
  if not relative_to then
    relative_to = relative_to_cwd
  end
  local relative_path = relative_to(position.path)

  local function get_line_number()
    if position.type == "test" then
      return position.range[1] + 1
    end
  end

  local line_number = get_line_number()
  if line_number then
    return string.format(
      "IExUnit.run(%q, line: %s, seed: %s, output_dir: %q)",
      relative_path,
      line_number,
      seed,
      output_dir
    )
  else
    return string.format("IExUnit.run(%q, seed: %s, output_dir: %q)", position.path, seed, output_dir)
  end
end

function M.iex_watch_command(results_path, maybe_compile_error_path, seed)
  -- the `&& cat maybe_compile_error_path` just for the case where encountering a compile error
  return string.format(
    "(tail -n 50 -f %s %s &) | grep -q %s && cat %s",
    results_path,
    maybe_compile_error_path,
    seed,
    maybe_compile_error_path
  )
end

local function build_formatters(extra_formatters)
  -- tables need to be copied by value
  local default_formatters = { "NeotestElixir.Formatter" }
  local formatters = { unpack(default_formatters) }
  vim.list_extend(formatters, extra_formatters)

  local result = {}
  for _, formatter in ipairs(formatters) do
    table.insert(result, "--formatter")
    table.insert(result, formatter)
  end

  return result
end

---@param position neotest.Position
---@return string[]
local function test_target(position, relative_to)
  -- Dependency injection for testing
  if not relative_to then
    relative_to = relative_to_cwd
  end

  local relative_path = relative_to(position.path)

  if position.type == "test" then
    local line = position.range[1] + 1
    return { relative_path .. ":" .. line }
  else
    return { relative_path }
  end
end

local function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end

M.plugin_path = Path.new(script_path()):parent():parent()

-- TODO: dirty version -- make it public only for testing
M.json_encoder_path = (M.plugin_path / "neotest_elixir/json_encoder.ex").filename
M.exunit_formatter_path = (M.plugin_path / "neotest_elixir/formatter.ex").filename
local mix_interactive_runner_path = (M.plugin_path / "neotest_elixir/test_interactive_runner.ex").filename

local function options_for_task(mix_task)
  if mix_task == "test.interactive" then
    return {
      "-r",
      mix_interactive_runner_path,
      "-e",
      "Application.put_env(:mix_test_interactive, :runner, NeotestElixir.TestInteractiveRunner)",
    }
  else
    return {
      "-r",
      M.json_encoder_path,
      "-r",
      M.exunit_formatter_path,
    }
  end
end

function M.build_mix_command(
  position,
  mix_task_func,
  extra_formatters_func,
  mix_task_args_func,
  neotest_args,
  relative_to_func
)
  return vim.tbl_flatten({
    {
      "elixir",
    },
    -- deferent tasks have different options
    -- for example, `test.interactive` needs to load a custom runner
    options_for_task(mix_task_func()),
    {
      "-S",
      "mix",
      mix_task_func(), -- `test` is default
    },
    -- default is ExUnit.CLIFormatter
    build_formatters(extra_formatters_func()),
    -- default is {}
    -- maybe `test.interactive` has different args with `test`
    mix_task_args_func(),
    neotest_args.extra_args or {},
    -- test file or directory or testfile:line
    test_target(position, relative_to_func),
  })
end

-- public only for testing
function M.iex_start_command(opened_filename)
  local filepath = opened_filename or vim.fn.expand("%:p")
  local function is_in_umbrella_project()
    return string.find(filepath, "/apps/") ~= nil
  end

  local function child_app_root_dir()
    local umbrella_root = string.match(filepath, "(.*/apps/)"):sub(1, -7)
    local child_root = string.match(filepath, "(.*/apps/[%w_]+)")
    return Path:new(child_root):make_relative(umbrella_root)
  end

  -- generate a starting command for the iex terminal
  local runner_path = (M.plugin_path / "neotest_elixir/iex-unit/lib/iex_unit.ex").filename
  local start_code = "IExUnit.start()"
  local configuration_code = "ExUnit.configure(formatters: [NeotestElixir.Formatter, ExUnit.CLIFormatter])"
  local start_command = string.format(
    "MIX_ENV=test iex --no-pry -S mix run -r %q -r %q -r %q -e %q -e %q",
    M.json_encoder_path,
    M.exunit_formatter_path,
    runner_path,
    start_code,
    configuration_code
  )

  if not is_in_umbrella_project() then
    return start_command
  end

  local function ends_with(cwd, relatived)
    local relatived_len = string.len(relatived)
    return string.sub(cwd, -relatived_len) == relatived
  end

  local child_root_relatived = child_app_root_dir()
  if not ends_with(vim.fn.getcwd(), child_root_relatived) then
    return string.format("cd %s && %s", child_root_relatived, start_command)
  else
    return start_command
  end
end

function M.get_or_create_iex_term(id, direction_func)
  local ok, toggleterm = pcall(require, "toggleterm")
  if not ok then
    vim.notify("Please install `toggleterm.nvim` first", vim.log.levels.ERROR)
  end

  local toggleterm_terminal = require("toggleterm.terminal")
  local term = toggleterm_terminal.get(id)

  if term == nil then
    toggleterm.exec(M.iex_start_command(), id, nil, nil, "horizontal")
    term = toggleterm_terminal.get_or_create_term(id)
    return term
  else
    return term
  end
end

function M.generate_seed()
  local seed_str, _ = string.gsub(vim.fn.reltimestr(vim.fn.reltime()), "(%d+).(%d+)", "%1%2")
  return tonumber(seed_str)
end

function M.create_and_clear(path)
  local x = io.open(path, "w")
  if x then
    x:write("")
    x:close()
  end
end

return M
