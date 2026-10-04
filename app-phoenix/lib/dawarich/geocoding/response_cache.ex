defmodule Dawarich.Geocoding.ResponseCache do
  @moduledoc false

  alias Dawarich.TtlCache

  @ttl_ms 86_400_000

  def get(key) do
    case TtlCache.lookup({__MODULE__, key}) do
      {:ok, body} when is_binary(body) and body != "" -> {:ok, body}
      _ -> :error
    end
  end

  def put(key, body) do
    TtlCache.put({__MODULE__, key}, body, @ttl_ms)
    :ok
  end
end
