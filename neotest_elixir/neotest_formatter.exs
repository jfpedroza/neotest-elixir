defmodule NeotestElixirFormatter do
  @moduledoc """
  A custom ExUnit formatter to provide output that is easier to parse.
  """
  use GenServer

  @impl true
  def init(_opts) do
    config = %{
      failure_count: 0
    }

    {:ok, config}
  end

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{} = test}, config) do
    config = update_count(test, config)
    output = %{id: make_id(test), status: make_status(test), output: make_output(test, config)}
    IO.puts(Jason.encode!(output))

    {:noreply, config}
  end

  def handle_cast(_msg, config) do
    {:noreply, config}
  end

  defp update_count(%ExUnit.Test{state: {:failed, _}}, config) do
    %{config | failure_count: config.failure_count + 1}
  end

  defp update_count(%ExUnit.Test{}, config), do: config

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

  defp make_output(%ExUnit.Test{state: {:failed, failures}} = test, config) do
    ExUnit.Formatter.format_test_failure(test, failures, config.failure_count, 80, &formatter/2)
  end

  defp make_output(%ExUnit.Test{state: {:skipped, due_to}}, _config) do
    "Skipped #{due_to}"
  end

  defp make_output(%ExUnit.Test{state: {:excluded, due_to}}, _config) do
    "Excluded #{due_to}"
  end

  defp make_output(%ExUnit.Test{}, _config), do: nil

  defp formatter(_, msg) do
    msg
  end
end
