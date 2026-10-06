defmodule Dawarich.Photos.ProviderCache do
  @moduledoc false
  alias Dawarich.{RailsCache, Redis}
  alias Dawarich.RailsCache.Wire

  @photo_keys ~w(id latitude longitude localDateTime capturedAt originalFileName city state country type orientation source)
  def term(photos),
    do: Enum.map(photos, fn photo -> {:object, Enum.map(@photo_keys, &{&1, photo[&1]})} end)

  def key(user, from, to), do: "photos_#{user}_v2_#{from}_#{to}"
  def token_key(user), do: "dawarich/photoprism_preview_token_#{user}"

  def get(key) do
    case RailsCache.get(key) do
      {:ok, value} -> {:ok, normalize(value)}
      _ -> :miss
    end
  end

  def put(key, value, seconds \\ 1800) do
    expires = System.system_time(:microsecond) / 1_000_000 + seconds
    payload = IO.iodata_to_binary([<<4, 8>>, marshal(value)])
    wire = <<0, 17, 1, expires::little-float-64, -1::little-signed-32, payload::binary>>
    Redis.cache_command(["SET", key, wire, "EX", to_string(seconds)])
  end

  def token(user) do
    case get(token_key(user)) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  def put_token(user, value) do
    bytes =
      if is_nil(value),
        do: Wire.encode_boolean(nil, expires_at: nil),
        else: Wire.encode(value, expires_at: -1)

    Redis.cache_command(["SET", token_key(user), bytes])
  end

  def invalidate(user) do
    for pattern <- ["photos_#{user}_v2_*", "photos_search/#{user}/*"],
        do: delete_matching(pattern, "0")

    Redis.cache_command(["UNLINK", token_key(user)])
    :ok
  end

  defp delete_matching(pattern, cursor) do
    case Redis.cache_command(["SCAN", cursor, "MATCH", pattern, "COUNT", "100"]) do
      {:ok, [next, keys]} ->
        if keys != [], do: Redis.cache_command(["UNLINK" | keys])
        if next != "0", do: delete_matching(pattern, next)

      _ ->
        :ok
    end
  end

  defp normalize({:ruby_symbol, name}), do: name
  defp normalize(%Dawarich.RailsCache.Value{value: value}) when is_binary(value), do: value
  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)

  defp normalize(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {normalize(k), normalize(v)} end)

  defp normalize(value), do: value

  defp marshal(nil), do: "0"
  defp marshal(true), do: "T"
  defp marshal(false), do: "F"
  defp marshal(n) when is_integer(n), do: ["i", long(n)]

  defp marshal(n) when is_float(n),
    do: ["f", bytes(Dawarich.ReleaseMigrations.Effects.Support.RubyFloat.to_s(n))]

  defp marshal(s) when is_binary(s), do: ["I\"", bytes(s), long(1), ":", bytes("E"), "T"]
  defp marshal(list) when is_list(list), do: ["[", long(length(list)), Enum.map(list, &marshal/1)]

  defp marshal(map) when is_map(map) do
    keys =
      if Map.has_key?(map, "capturedAt"),
        do:
          ~w(id latitude longitude localDateTime capturedAt originalFileName city state country type orientation source),
        else: Map.keys(map)

    [
      "{",
      long(map_size(map)),
      Enum.map(keys, fn k -> [marshal(to_string(k)), marshal(map[k])] end)
    ]
  end

  defp bytes(value), do: [long(byte_size(value)), value]
  defp long(0), do: <<0>>
  defp long(n) when n in 1..122, do: <<n + 5>>
  defp long(n) when n in -123..-1, do: <<n - 5::signed-8>>

  defp long(n) when n > 0 do
    data = :binary.encode_unsigned(n, :little)
    [<<byte_size(data)>>, data]
  end

  defp long(n) do
    size = Enum.find(1..8, &(n >= -Integer.pow(256, &1)))
    [<<-size::signed-8>>, <<n::little-signed-size(size * 8)>>]
  end
end
