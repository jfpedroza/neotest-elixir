defmodule NeotestElixir.JsonEncoder do
  @moduledoc """
  A custom JSON encoder that doesn't use protocols based on [elixir-json](https://github.com/cblage/elixir-json).

  The encoder is embedded because that way we don't depend on a library being installed
  in the project and also we can't really add dependencies ourselves.
  """

  @acii_space 32

  def encode!(input) do
    do_encode(input)
  end

  defp do_encode(number) when is_number(number), do: to_string(number)
  defp do_encode(nil), do: "null"
  defp do_encode(true), do: "true"
  defp do_encode(false), do: "false"
  defp do_encode(atom) when is_atom(atom), do: do_encode(to_string(atom))

  defp do_encode(string) when is_binary(string) do
    [?", Enum.reverse(encode_binary(string, [])), ?"]
  end

  defp do_encode(map) when is_map(map) do
    content =
      Enum.map(map, fn {key, value} ->
        [do_encode(key), ": ", do_encode(value)]
      end)

    [?{, Enum.intersperse(content, ", "), ?}]
  end

  defp do_encode(list) when is_list(list) do
    content = Enum.map(list, &do_encode/1)

    [?[, Enum.intersperse(content, ", "), ?]]
  end

  defp encode_binary(<<>>, acc) do
    acc
  end

  defp encode_binary(<<head::utf8, tail::binary>>, acc) do
    encode_binary(tail, [encode_binary_character(head) | acc])
  end

  defp encode_binary_character(?"), do: [?\\, ?"]
  defp encode_binary_character(?\b), do: [?\\, ?b]
  defp encode_binary_character(?\f), do: [?\\, ?f]
  defp encode_binary_character(?\n), do: [?\\, ?n]
  defp encode_binary_character(?\r), do: [?\\, ?r]
  defp encode_binary_character(?\t), do: [?\\, ?t]
  defp encode_binary_character(?\\), do: [?\\, ?\\]

  defp encode_binary_character(char) when is_number(char) and char < @acii_space do
    [?\\, ?u | encode_hexadecimal_unicode_control_character(char)]
  end

  defp encode_binary_character(char), do: char

  defp encode_hexadecimal_unicode_control_character(char) when is_number(char) do
    char
    |> Integer.to_charlist(16)
    |> zeropad_hexadecimal_unicode_control_character()
  end

  defp zeropad_hexadecimal_unicode_control_character([a, b, c]), do: [?0, a, b, c]
  defp zeropad_hexadecimal_unicode_control_character([a, b]), do: [?0, ?0, a, b]
  defp zeropad_hexadecimal_unicode_control_character([a]), do: [?0, ?0, ?0, a]
  defp zeropad_hexadecimal_unicode_control_character(iolist) when is_list(iolist), do: iolist
end

# NeotestElixir.JsonEncoder.encode!(%{
#   a: 1,
#   b: nil,
#   c: true,
#   d: false,
#   e: :cool,
#   f: "some string",
#   g: [1, 2.0, "three"],
#   h: %{
#     "i" => "nested",
#     "j" => "map"
#   },
#   l: "some string with a \t and a \n",
#   m: "\0\3\a"
# })
# |> IO.puts()
