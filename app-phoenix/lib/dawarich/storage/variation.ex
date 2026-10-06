defmodule Dawarich.Storage.Variation do
  @moduledoc false
  alias Dawarich.{RailsMessages, RailsSecret}
  alias Dawarich.RailsCache.{Marshal, Value}
  defstruct [:transformations, :pairs, :key]

  def decode(signed, now \\ DateTime.utc_now()) do
    with {:ok, transforms} <- RailsMessages.verify_storage(signed, "variation", now) do
      build(transforms, signed)
    else
      _ -> legacy(signed, now)
    end
  end

  defp build(%{} = transforms, signed) do
    {:ok, %__MODULE__{transformations: transforms, pairs: ordered(signed, transforms), key: signed}}
  end
  defp build(_, _), do: :error

  defp ordered(signed, transforms) do
    with [data, _] <- String.split(signed, "--"),
         {:ok, bytes} <- Base.decode64(data),
         {:ok, value} <- Jason.decode(bytes, objects: :ordered_objects),
         %Jason.OrderedObject{values: pairs} <- value["_rails"]["data"] do
      pairs
    else
      _ -> Enum.to_list(transforms)
    end
  end

  defp legacy(signed, now) when is_binary(signed) do
    with [data, signature] <- String.split(signed, "--"),
         expected = mac(data),
         true <- byte_size(signature) == byte_size(expected) and Plug.Crypto.secure_compare(signature, expected),
         {:ok, bytes} <- Base.decode64(data),
         {:ok, envelope} <- Jason.decode(bytes),
         %{"_rails" => meta} <- envelope,
         true <- meta["pur"] == "variation",
         true <- live?(meta["exp"], now),
         {:ok, inner} <- Base.decode64(meta["message"]),
         {:ok, value} <- Marshal.decode(inner),
         %{} = transforms <- normalize(value) do
      {:ok, %__MODULE__{transformations: transforms, pairs: Enum.to_list(transforms), key: signed}}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end
  defp legacy(_, _), do: :error

  defp normalize(%Value{}), do: :error
  defp normalize({:ruby_symbol, name}), do: name
  defp normalize(value) when is_map(value), do: Map.new(value, fn {k,v} -> {normalize(k), normalize(v)} end)
  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value), do: value

  defp live?(nil, _now), do: true
  defp live?(exp, now) do
    case DateTime.from_iso8601(exp) do
      {:ok, at, _} -> DateTime.compare(now, at) == :lt
      _ -> false
    end
  end

  def sign(pairs) do
    data = RailsMessages.json(%{"_rails" => Jason.OrderedObject.new(data: Jason.OrderedObject.new(pairs), pur: "variation")}) |> Base.encode64()
    data <> "--" <> mac(data)
  end

  def default(variation, format) do
    pairs = [{"format", Map.get(variation.transformations, "format", format)} | Enum.reject(variation.pairs, &(elem(&1, 0) == "format"))]
    %{variation | transformations: Map.put_new(variation.transformations, "format", format), pairs: pairs, key: sign(pairs)}
  end

  def digest(variation), do: :crypto.hash(:sha, marshal(variation)) |> Base.encode64()
  def marshal(variation) do
    {body, _} = dump({:hash, variation.pairs}, %{})
    <<4, 8>> <> body
  end

  defp dump({:hash, pairs}, symbols) do
    {body, symbols} = Enum.reduce(pairs, {<<>>, symbols}, fn {k,v}, {acc, symbols} ->
      {key, symbols} = dump({:ruby_symbol, k}, symbols)
      {value, symbols} = dump(v, symbols)
      {acc <> key <> value, symbols}
    end)
    {"{" <> long(length(pairs)) <> body, symbols}
  end

  defp dump(%Jason.OrderedObject{values: pairs}, symbols), do: dump({:hash, pairs}, symbols)
  defp dump(value, symbols) when is_map(value), do: dump({:hash, Enum.to_list(value)}, symbols)
  defp dump({:ruby_symbol, value}, symbols) do
    case Map.fetch(symbols, value) do
      {:ok, index} -> {";" <> long(index), symbols}
      :error -> {":" <> long(byte_size(value)) <> value, Map.put(symbols, value, map_size(symbols))}
    end
  end
  defp dump(value, symbols) when is_binary(value) do
    {encoding, symbols} = dump({:ruby_symbol, "E"}, symbols)
    {"I\"" <> long(byte_size(value)) <> value <> long(1) <> encoding <> "T", symbols}
  end
  defp dump(value, symbols) when is_integer(value), do: {"i" <> long(value), symbols}
  defp dump(value, symbols) when is_float(value) do
    string = value |> Float.to_string() |> String.trim_trailing(".0")
    {"f" <> long(byte_size(string)) <> string, symbols}
  end
  defp dump(value, symbols) when is_list(value) do
    {body, symbols} = Enum.reduce(value, {<<>>, symbols}, fn value, {acc, symbols} ->
      {bytes, symbols} = dump(value, symbols)
      {acc <> bytes, symbols}
    end)
    {"[" <> long(length(value)) <> body, symbols}
  end
  defp dump(nil, symbols), do: {"0", symbols}
  defp dump(true, symbols), do: {"T", symbols}
  defp dump(false, symbols), do: {"F", symbols}

  defp long(0), do: <<0>>
  defp long(n) when n > 0 and n < 123, do: <<n+5>>
  defp long(n) when n < 0 and n > -124, do: <<n-5::signed>>
  defp long(n) do
    bytes = <<n::little-signed-32>> |> :binary.bin_to_list() |> Enum.reverse() |> Enum.drop_while(&(&1 == if(n < 0, do: 255, else: 0))) |> Enum.reverse() |> :binary.list_to_bin()
    size = byte_size(bytes)
    <<if(n < 0, do: -size, else: size)::signed>> <> bytes
  end

  defp mac(data), do: :crypto.mac(:hmac, :sha, RailsMessages.key(RailsSecret.fetch(), "ActiveStorage", 1000, 64), data) |> Base.encode16(case: :lower)
end
