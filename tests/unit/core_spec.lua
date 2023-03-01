local core = require("neotest-elixir.core")

describe("build_iex_test_command", function()
  local relative_to

  before_each(function()
    -- always return the input
    relative_to = function(path)
      return path
    end
  end)

  it("should return the correct command for a test", function()
    local position = {
      type = "test",
      path = "example_test.exs",
      range = { 1, 2 },
    }
    local output_dir = "test_output"
    local seed = 1234

    local actual = core.build_iex_test_command(position, output_dir, seed, relative_to)

    assert.are.equal('IExUnit.run("example_test.exs", line: 2, seed: 1234, output_dir: "test_output")', actual)
  end)

  it("should return the correct command for a file", function()
    local position = {
      type = "file",
      path = "test/neotest_elixir/core_spec.exs",
      range = { 1, 2 },
    }
    local output_dir = "test_output"
    local seed = 1234

    local actual = core.build_iex_test_command(position, output_dir, seed, relative_to)

    assert.are.equal('IExUnit.run("test/neotest_elixir/core_spec.exs", seed: 1234, output_dir: "test_output")', actual)
  end)

  it("should return the correct command for the folder", function()
    local position = {
      type = "folder",
      path = "test/neotest_elixir",
      range = { 1, 2 },
    }
    local output_dir = "test_output"
    local seed = 1234

    local actual = core.build_iex_test_command(position, output_dir, seed, relative_to)

    assert.are.equal('IExUnit.run("test/neotest_elixir", seed: 1234, output_dir: "test_output")', actual)
  end)
end)

describe("iex_watch_command", function()
  it("should return the correct command", function()
    local results_path = "results_path"
    local maybe_compile_error_path = "maybe_compile_error_path"
    local seed = 1234

    local actual = core.iex_watch_command(results_path, maybe_compile_error_path, seed)

    assert.are.equal(
      "(tail -n 50 -f results_path maybe_compile_error_path &) | grep -q 1234 && cat maybe_compile_error_path",
      actual
    )
  end)
end)

describe("get_or_create_iex_term", function()
  local function starts_with(str, start)
    return str:sub(1, #start) == start
  end

  it("should create a new iex term if none exists", function()
    local actual = core.get_or_create_iex_term(42)
    assert.are.equal(42, actual.id)
  end)

  it("should cd to the child app if the opened_file in umbrella project", function()
    local actual = core.iex_start_command("/root/apps/child_app1/test/child_app_test.exs")
    assert.is.True(starts_with(actual, "cd apps/child_app1 && "))
  end)

  it("should not cd to the some place when in a normal app", function()
    local actual = core.iex_start_command("/root/my_app/test/my_app_test.exs")
    assert.is.False(starts_with(actual, "iex -S mix"))
  end)
end)

describe("build_mix_command", function()
  local mix_task_func
  local extra_formatter_func
  local mix_task_args_func
  local relative_to

  before_each(function()
    mix_task_func = function()
      return "test"
    end
    extra_formatter_func = function()
      return { "ExUnit.CLIFormatter" }
    end
    mix_task_args_func = function()
      return {}
    end
    relative_to = function(path)
      return path
    end
  end)

  it("should return the correct command for a test", function()
    local position = {
      type = "test",
      path = "example_test.exs",
      range = { 1, 2 },
    }

    local actual_tbl =
      core.build_mix_command(position, mix_task_func, extra_formatter_func, mix_task_args_func, {}, relative_to)

    local expected = string.format(
      "elixir -r %s -r %s -S mix test --formatter NeotestElixir.Formatter --formatter ExUnit.CLIFormatter example_test.exs:2",
      core.json_encoder_path,
      core.exunit_formatter_path
    )
    assert.are.equal(expected, table.concat(actual_tbl, " "))
  end)

  it("should not return line args for a file test", function()
    local position = {
      type = "file",
      path = "example_test.exs",
      range = { 1, 2 },
    }

    local actual_tbl =
      core.build_mix_command(position, mix_task_func, extra_formatter_func, mix_task_args_func, {}, relative_to)

    local expected = string.format(
      "elixir -r %s -r %s -S mix test --formatter NeotestElixir.Formatter --formatter ExUnit.CLIFormatter example_test.exs",
      core.json_encoder_path,
      core.exunit_formatter_path
    )
    assert.are.equal(expected, table.concat(actual_tbl, " "))
  end)
end)
