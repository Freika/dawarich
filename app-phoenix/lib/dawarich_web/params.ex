defmodule DawarichWeb.Params do
  @moduledoc false

  def ruby_to_i(value) when is_binary(value) do
    case Regex.run(~r/\A\s*([+-]?\d+(?:_\d+)*)/, value) do
      [_, digits] -> digits |> String.replace("_", "") |> String.to_integer()
      nil -> 0
    end
  end

  def ruby_to_i(_value), do: 0

  def to_query(params, namespace \\ nil) when is_map(params) do
    pairs =
      for {key, value} <- params, value not in [[], %{}] do
        encode(value, if(namespace, do: "#{namespace}[#{key}]", else: to_string(key)))
      end

    pairs
    |> then(&if(String.contains?(to_string(namespace), "[]"), do: &1, else: Enum.sort(&1)))
    |> Enum.join("&")
  end

  defp encode(value, key) when is_map(value), do: to_query(value, key)

  defp encode(values, key) when is_list(values),
    do: Enum.map_join(values, "&", &encode(&1, key <> "[]"))

  defp encode(value, key),
    do: URI.encode_www_form(key) <> "=" <> URI.encode_www_form(to_string(value))
end
