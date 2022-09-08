defmodule NeotestElixirFormatter do
  @moduledoc """
  A custom ExUnit formatter to provide output that is easier to parse.
  """
  use GenServer

  require Logger

  @impl true
  def init(opts) do
    output_dir = System.fetch_env!("NEOTEST_OUTPUT_DIR")
    File.mkdir_p!(output_dir)
    results_path = Path.join(output_dir, "results")
    results_io_device = File.open!(results_path, [:write, :delayed_write, :utf8])

    config = %{
      output_dir: output_dir,
      results_path: results_path,
      results_io_device: results_io_device,
      colors: colors(opts),
      test_counter: 0,
      failure_counter: 0
    }

    {:ok, config}
  end

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{} = test}, config) do
    try do
      config =
        config
        |> update_test_counter()
        |> update_failure_counter(test)

      id = make_id(test)

      output = %{
        id: id,
        status: make_status(test),
        output: save_test_output(test, config, id),
        errors: make_errors(test)
      }

      IO.puts(config.results_io_device, json_encode!(output))

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

  defp update_test_counter(config) do
    %{config | test_counter: config.test_counter + 1}
  end

  defp update_failure_counter(config, %ExUnit.Test{state: {:failed, _}}) do
    %{config | failure_counter: config.failure_counter + 1}
  end

  defp update_failure_counter(config, %ExUnit.Test{}), do: config

  defp make_id(%ExUnit.Test{tags: tags} = _test) do
    "#{Path.relative_to_cwd(tags[:file])}:#{tags[:line]}"
  end

  defp make_status(%ExUnit.Test{state: nil}), do: "passed"
  defp make_status(%ExUnit.Test{state: {:failed, _}}), do: "failed"
  defp make_status(%ExUnit.Test{state: {:skipped, _}}), do: "skipped"
  defp make_status(%ExUnit.Test{state: {:excluded, _}}), do: "skipped"
  defp make_status(%ExUnit.Test{state: {:invalid, _}}), do: "failed"

  defp save_test_output(%ExUnit.Test{} = test, config, id) do
    output = make_output(test, config)

    if output do
      file = Path.join(config.output_dir, "test_output_#{:erlang.phash2(id)}")

      if File.exists?(file) do
        File.write!(file, ["\n\n", output], [:append])
      else
        File.write!(file, output)
      end

      file
    end
  end

  defp make_output(%ExUnit.Test{state: {:failed, failures}} = test, config) do
    ExUnit.Formatter.format_test_failure(
      test,
      failures,
      config.failure_counter,
      80,
      &formatter(&1, &2, config)
    )
  end

  defp make_output(%ExUnit.Test{state: {:skipped, due_to}}, _config) do
    "Skipped #{due_to}"
  end

  defp make_output(%ExUnit.Test{state: {:excluded, due_to}}, _config) do
    "Excluded #{due_to}"
  end

  defp make_output(%ExUnit.Test{}, _config), do: nil

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

  case System.get_env("NEOTEST_JSON_MODULE", "Jason") do
    "Jason" ->
      def json_encode!(data) do
        Jason.encode_to_iodata!(data)
      end

    "Poison" ->
      def json_encode!(data) do
        Poison.encode!(data, iodata: true)
      end

    "embedded" ->
      def json_encode!(data) do
        NeotestElixir.JsonEncoder.encode!(data)
      end
  end
end
