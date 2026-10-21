defmodule Dawarich.Tracks.PerUserLock do
  @moduledoc false

  alias Dawarich.State.Lease

  def key(user_id), do: "tracks:per_user_lock:#{user_id}"

  def with_user_lock(repo, user_id, fun, opts \\ []) when is_function(fun, 0),
    do: Lease.with_lease(repo, key(user_id), fun, opts)
end
