defmodule Dawarich.RawData.Contention do
  @moduledoc false

  @codes [:deadlock_detected, :lock_not_available, :query_canceled]

  def retry(opts, fun, attempt \\ 0) do
    fun.()
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] in @codes and attempt < 3 do
        Keyword.get(opts, :sleep, &Process.sleep/1).(100 * (attempt + 1) + :rand.uniform(50))
        retry(opts, fun, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end
end
