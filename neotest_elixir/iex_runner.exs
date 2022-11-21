defmodule NeotestElixir.IExRunner do
  def run do
    config = parse_args(System.argv())
    setup_exunit(config)
    Code.compiler_options(ignore_module_conflict: true)

    loop()
  end

  defp parse_args(argv) do
    {parsed, []} = OptionParser.parse!(argv, strict: [formatter: :keep])

    formatters =
      parsed
      |> Keyword.get_values(:formatter)
      |> Enum.map(fn formatter ->
        Module.safe_concat("Elixir", formatter)
      end)

    %{formatters: formatters}
  end

  defp setup_exunit(config) do
    if File.exists?("test/test_helper.exs") do
      Code.eval_file("test/test_helper.exs", File.cwd!())
    end

    ExUnit.configure(autorun: false, formatters: config.formatters)
  end

  defp loop do
    case IO.read(:line) do
      :eof ->
        :ok

      {:error, reason} ->
        raise "received error #{inspect(reason)}."

      chardata ->
        data = IO.chardata_to_string(chardata)
        handle_input(String.trim(data))
        loop()
    end
  end

  defp handle_input(input) do
    case String.split(input, ":", trim: true) do
      [file, line] ->
        configure_line(line)
        test_files([file])

      [path] ->
        reset_includes()

        path
        |> expand_paths()
        |> test_files()
    end
  end

  defp configure_line(line) do
    ExUnit.configure(exclude: [:test], include: [line: line])
  end

  defp reset_includes do
    ExUnit.configure(exclude: [], include: [])
  end

  defp expand_paths(path) do
    if path == "." do
      Mix.Utils.extract_files([path <> "/test"], "*_test.exs")
    else
      Mix.Utils.extract_files([path], "*_test.exs")
    end
  end

  defp test_files(files) do
    IEx.Helpers.recompile()

    with {:ok, _, _} <- Kernel.ParallelCompiler.compile(files) do
      if function_exported?(ExUnit.Server, :modules_loaded, 1) do
        ExUnit.Server.modules_loaded(false)
      else
        ExUnit.Server.modules_loaded()
      end

      ExUnit.run()
    end
  end
end

NeotestElixir.IExRunner.run()
