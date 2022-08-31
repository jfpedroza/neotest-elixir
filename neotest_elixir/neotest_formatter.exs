defmodule NeotestElixirFormatter do
  @moduledoc """
  A custom ExUnit formatter to provide output that is easier to parse.
  """
  use GenServer

  require Logger

  @impl true
  def init(opts) do
    output_dir = System.fetch_env!("NEOTEST_OUTPUT_DIR")
    File.mkdir!(output_dir)

    config = %{
      output_dir: output_dir,
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

      output = %{
        id: make_id(test),
        status: make_status(test),
        output: save_test_output(test, config)
      }

      IO.puts(Jason.encode!(output))

      {:noreply, config}
    catch
      kind, reason ->
        Logger.error(Exception.format(kind, reason, __STACKTRACE__))
        {:noreply, config}
    end
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

  defp make_id(%ExUnit.Test{} = test) do
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
      file = Path.join(config.output_dir, "test_output_#{config.test_counter}")
      File.write!(file, output)
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
