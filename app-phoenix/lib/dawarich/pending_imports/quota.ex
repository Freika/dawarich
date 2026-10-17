defmodule Dawarich.PendingImports.Quota do
  @moduledoc false
  alias Dawarich.Redis
  @limit 10 * 1024 * 1024 * 1024

  def key(now), do: "pending_imports/storage_bytes/#{DateTime.to_date(now)}"

  def reserve(bytes, key) do
    {:ok, used} = Redis.cache_command(["INCRBY", key, to_string(bytes)])
    {:ok, _} = Redis.cache_command(["EXPIRE", key, "172800", "NX"])

    if used <= @limit do
      :ok
    else
      release(bytes, key)
      {:error, :capacity}
    end
  end

  def release(bytes, key), do: Redis.cache_command(["DECRBY", key, to_string(bytes)])

  def with_reservation(bytes, key, fun) do
    with :ok <- reserve(bytes, key) do
      try do
        fun.()
      rescue
        error ->
          release(bytes, key)
          reraise error, __STACKTRACE__
      end
    end
  end
end
