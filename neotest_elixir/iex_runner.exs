defmodule NeotestElixir.IExRunner do
  def run do
    args = System.argv()
    IO.inspect(args, label: "Got args")

    loop()
  end

  defp loop do
    case IO.read(:line) do
      :eof ->
        IO.puts("Received EOF. Stopping")

      {:error, reason} ->
        IO.puts("Received error #{inspect(reason)}. Stopping")

      chardata ->
        data = IO.chardata_to_string(chardata)
        IO.inspect(data, label: "Got input")
        loop()
    end
  end
end

NeotestElixir.IExRunner.run()
