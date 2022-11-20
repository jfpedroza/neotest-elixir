defmodule NeotestElixir.TestInteractiveRunner do
  @moduledoc """
  Copyright (c) 2021-2022 Randy Coulman
  Copyright (c) 2022 Jhon Pedroza

  A copy of https://github.com/randycoulman/mix_test_interactive/blob/main/lib/mix_test_interactive/port_runner.ex
  modified to work with Neotest.
  """

  @application :mix_test_interactive
  @type runner ::
          (String.t(), [String.t()], keyword() ->
             {Collectable.t(), exit_status :: non_neg_integer()})
  @type os_type :: {atom(), atom()}

  alias MixTestInteractive.Config

  @doc """
  Run tests based on the current configuration.
  """
  @spec run(Config.t(), [String.t()], os_type(), runner()) :: :ok
  def run(
        config,
        args,
        os_type \\ :os.type(),
        runner \\ &System.cmd/3
      ) do
    task_command = [config.task | args]
    do_commands = [neotest_requires(), task_command]

    case os_type do
      {:win32, _} ->
        runner.("mix", flatten_do_commands(do_commands),
          env: [{"MIX_ENV", "test"}],
          into: IO.stream(:stdio, :line)
        )

      _ ->
        do_commands = [enable_ansi(task_command) | do_commands]

        Path.join(:code.priv_dir(@application), "zombie_killer")
        |> runner.(["mix" | flatten_do_commands(do_commands)],
          env: [{"MIX_ENV", "test"}],
          into: IO.stream(:stdio, :line)
        )
    end

    :ok
  end

  defp neotest_requires do
    plugin = System.fetch_env!("NEOTEST_PLUGIN_PATH")
    json_encoder = "#{plugin}/neotest_elixir/json_encoder.ex"
    exunit_formatter = "#{plugin}/neotest_elixir/formatter.ex"
    ["run", "-r", json_encoder, "-r", exunit_formatter]
  end

  defp enable_ansi(task_command) do
    enable_command = "Application.put_env(:elixir, :ansi_enabled, true);"

    if Enum.member?(task_command, "--no-start") do
      ["run", "--no-start", "-e", enable_command]
    else
      ["run", "-e", enable_command]
    end
  end

  defp flatten_do_commands(do_commands) do
    commands = do_commands |> Enum.intersperse([","]) |> Enum.concat()
    ["do" | commands]
  end
end
