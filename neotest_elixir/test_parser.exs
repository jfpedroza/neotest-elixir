alias NeotestElixir.JsonEncoder
files = System.argv()

if files != [] do
  {:ok, _} = Application.ensure_all_started(:ex_unit)

  for file <- files,
      {module, _} <- Code.require_file(file),
      function_exported?(module, :__ex_unit__, 0) do
    %ExUnit.TestModule{} = test_module = module.__ex_unit__()

    tests =
      for test <- test_module.tests do
        line = test.tags.line

        %{
          type: "test",
          path: test.tags.file,
          name: test.name,
          range: [line - 1, 0, line + 1, 0]
        }
      end

    file_position = %{
      type: "file",
      path: file,
      name: Path.basename(file),
      range: [0, 0, 1000, 0]
    }

    file_position
    |> JsonEncoder.encode!()
    |> IO.puts()

    tests
    |> Enum.reverse()
    |> Enum.each(fn test ->
      test
      |> JsonEncoder.encode!()
      |> IO.puts()
    end)
  end
end
