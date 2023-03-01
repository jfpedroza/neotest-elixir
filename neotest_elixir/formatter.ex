defmodule NeotestElixir.Formatter do
  @moduledoc """
  A custom ExUnit formatter to provide output that is easier to parse.
  """
  use GenServer

  require Logger

  alias NeotestElixir.JsonEncoder

  @impl true
  def init(opts) do
    output_dir = opts[:output_dir] || System.fetch_env!("NEOTEST_OUTPUT_DIR")
    File.mkdir_p!(output_dir)
    results_path = Path.join(output_dir, "results")
    write_delay = String.to_integer(System.get_env("NEOTEST_WRITE_DELAY") || "100")

    results_io_device =
      File.open!(results_path, [:append, {:delayed_write, 64 * 1000, write_delay}, :utf8])

    config = %{
      seed: opts[:seed],
      output_dir: output_dir,
      results_path: results_path,
      results_io_device: results_io_device,
      colors: colors(opts),
      test_counter: 0,
      failure_counter: 0,
      tests: %{}
    }

    {:ok, config}
  end

  @impl true
  def handle_cast({:module_started, %ExUnit.TestModule{} = test_module}, config) do
    config = add_test_module(config, test_module)
    {:noreply, config}
  end

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{} = test}, config) do
    try do
      config =
        config
        |> update_test_counter()
        |> update_failure_counter(test)

      id = get_test_config(test, config).id

      output = %{
        seed: config[:seed],
        id: id,
        status: make_status(test),
        output: save_test_output(test, config),
        errors: make_errors(test)
      }

      IO.puts(config.results_io_device, JsonEncoder.encode!(output))

      {:noreply, config}
    catch
      kind, reason ->
        Logger.error(Exception.format(kind, reason, __STACKTRACE__))
        {:noreply, config}
    end
  end

  def handle_cast({:suite_finished, _}, config) do
    File.close(config.results_io_device)
    {:noreply, config}
  end

  def handle_cast(_msg, config) do
    {:noreply, config}
  end

  defp add_test_module(config, %ExUnit.TestModule{} = test_module) do
    tests =
      test_module.tests
      |> Enum.group_by(& &1.tags.line)
      |> Stream.flat_map(fn
        {_, tests} ->
          single_test? =
            case tests do
              [_] -> true
              [_ | _] -> false
            end

          Stream.map(tests, fn test ->
            # Doctests are handled as dynamic even if it's a single test
            dynamic? = test.tags.test_type == :doctest or not single_test?
            id = make_id(dynamic?, test)
            output_file = Path.join(config.output_dir, "test_output_#{:erlang.phash2(id)}")
            # The file may exist in some cases (multiple runs with the same output dir)
            File.rm(output_file)
            test_config = %{id: id, dynamic?: dynamic?, output_file: output_file}

            {{test.module, test.name}, test_config}
          end)
      end)
      |> Map.new()

    update_in(config.tests, &Map.merge(&1, tests))
  end

  defp get_test_config(%ExUnit.Test{} = test, config) do
    Map.fetch!(config.tests, {test.module, test.name})
  end

  defp dynamic?(%ExUnit.Test{} = test, config), do: get_test_config(test, config).dynamic?

  defp update_test_counter(config) do
    %{config | test_counter: config.test_counter + 1}
  end

  defp update_failure_counter(config, %ExUnit.Test{state: {:failed, _}}) do
    %{config | failure_counter: config.failure_counter + 1}
  end

  defp update_failure_counter(config, %ExUnit.Test{}), do: config

  defp make_id(true = _dynamic?, %ExUnit.Test{tags: tags}) do
    "#{Path.relative_to_cwd(tags[:file])}:#{tags[:line]}"
  end

  defp make_id(false, %ExUnit.Test{} = test) do
    file = test.tags.file
    name = remove_prefix(test)

    if describe = test.tags.describe do
      "#{file}::#{describe}::#{name}"
    else
      "#{file}::#{name}"
    end
  end

  defp remove_prefix(%ExUnit.Test{} = test) do
    name = to_string(test.name)

    prefix =
      if test.tags.describe do
        "#{test.tags.test_type} #{test.tags.describe} "
      else
        "#{test.tags.test_type} "
      end

    String.replace_prefix(name, prefix, "")
  end

  defp make_status(%ExUnit.Test{state: nil}), do: "passed"
  defp make_status(%ExUnit.Test{state: {:failed, _}}), do: "failed"
  defp make_status(%ExUnit.Test{state: {:skipped, _}}), do: "skipped"
  defp make_status(%ExUnit.Test{state: {:excluded, _}}), do: "skipped"
  defp make_status(%ExUnit.Test{state: {:invalid, _}}), do: "failed"

  defp save_test_output(%ExUnit.Test{} = test, config) do
    output = make_output(test, config)

    if output do
      file = get_test_config(test, config).output_file

      if File.exists?(file) do
        File.write!(file, ["\n\n", output], [:append])
      else
        File.write!(file, output)
      end

      file
    end
  end

  defp make_output(%ExUnit.Test{state: {:failed, failures}} = test, config) do
    failures =
      ExUnit.Formatter.format_test_failure(
        test,
        failures,
        config.failure_counter,
        80,
        &formatter(&1, &2, config)
      )

    [failures, format_captured_logs(test.logs)]
  end

  defp make_output(%ExUnit.Test{state: {:skipped, due_to}}, _config) do
    "Skipped #{due_to}"
  end

  defp make_output(%ExUnit.Test{state: {:excluded, due_to}}, _config) do
    "Excluded #{due_to}"
  end

  defp make_output(%ExUnit.Test{state: {:invalid, module}}, _config) do
    "Test is invalid. `setup_all` for #{inspect(module.name)} failed"
  end

  defp make_output(%ExUnit.Test{state: nil} = test, config) do
    if dynamic?(test, config) do
      "#{test.name} passed in #{format_us(test.time)}ms"
    else
      "Test passed in #{format_us(test.time)}ms"
    end
  end

  defp format_captured_logs(""), do: []

  defp format_captured_logs(output) do
    indent = "\n     "
    output = String.replace(output, "\n", indent)
    ["     The following output was logged:", indent | output]
  end

  defp make_errors(%ExUnit.Test{state: {:failed, failures}} = test) do
    Enum.map(failures, fn failure ->
      {message, stack} = make_error_message(failure)
      %{message: message, line: make_error_line(stack, test)}
    end)
  end

  defp make_errors(%ExUnit.Test{}), do: []

  defp make_error_message(failure) do
    case failure do
      {{:EXIT, _}, {reason, [_ | _] = stack}, _stack} ->
        {extract_message(:error, reason), stack}

      {kind, reason, stack} ->
        {extract_message(kind, reason), stack}
    end
  end

  defp extract_message(:error, %ExUnit.AssertionError{message: message}), do: message

  defp extract_message(kind, reason) do
    kind
    |> Exception.format_banner(reason)
    |> String.split("\n", trim: true)
    |> hd()
    |> String.replace_prefix("** ", "")
  end

  defp make_error_line(stack, %ExUnit.Test{} = test) do
    if test_call = find_exact_test_stack_match(stack, test) do
      line_from_stack_entry(test_call)
    else
      stack
      |> find_anon_fun_test_stack_match(test)
      |> line_from_stack_entry()
    end
  end

  defp find_exact_test_stack_match(stack, test) do
    Enum.find(stack, fn {module, function, _, _} ->
      module == test.module and function == test.name
    end)
  end

  defp find_anon_fun_test_stack_match(stack, test) do
    fun_prefix = "-#{test.name}/1-"

    Enum.find(stack, fn {module, function, _, _} ->
      module == test.module and String.starts_with?(to_string(function), fun_prefix)
    end)
  end

  defp line_from_stack_entry({_, _, _, location}) do
    if line = location[:line] do
      line - 1
    end
  end

  defp line_from_stack_entry(nil), do: nil

  # Format us as ms, from CLIFormatter
  defp format_us(us) do
    us = div(us, 10)

    if us < 10 do
      "0.0#{us}"
    else
      us = div(us, 10)
      "#{div(us, 10)}.#{rem(us, 10)}"
    end
  end

  # Color styles, copied from CLIFormatter

  defp colorize(escape, string, %{colors: colors}) do
    if colors[:enabled] do
      [escape, string, :reset]
      |> IO.ANSI.format_fragment(true)
      |> IO.iodata_to_binary()
    else
      string
    end
  end

  defp colorize_doc(escape, doc, %{colors: colors}) do
    if colors[:enabled] do
      Inspect.Algebra.color(doc, escape, %Inspect.Opts{syntax_colors: colors})
    else
      doc
    end
  end

  defp formatter(:diff_enabled?, _, %{colors: colors}), do: colors[:enabled]

  defp formatter(:error_info, msg, config), do: colorize(:red, msg, config)

  defp formatter(:extra_info, msg, config), do: colorize(:cyan, msg, config)

  defp formatter(:location_info, msg, config), do: colorize([:bright, :black], msg, config)

  defp formatter(:diff_delete, doc, config), do: colorize_doc(:diff_delete, doc, config)

  defp formatter(:diff_delete_whitespace, doc, config),
    do: colorize_doc(:diff_delete_whitespace, doc, config)

  defp formatter(:diff_insert, doc, config), do: colorize_doc(:diff_insert, doc, config)

  defp formatter(:diff_insert_whitespace, doc, config),
    do: colorize_doc(:diff_insert_whitespace, doc, config)

  defp formatter(:blame_diff, msg, %{colors: colors} = config) do
    if colors[:enabled] do
      colorize(:red, msg, config)
    else
      "-" <> msg <> "-"
    end
  end

  defp formatter(_, msg, _config), do: msg

  @default_colors [
    diff_delete: :red,
    diff_delete_whitespace: IO.ANSI.color_background(2, 0, 0),
    diff_insert: :green,
    diff_insert_whitespace: IO.ANSI.color_background(0, 2, 0)
  ]

  defp colors(opts) do
    @default_colors
    |> Keyword.merge(opts[:colors])
    |> Keyword.put_new(:enabled, IO.ANSI.enabled?())
  end
end
