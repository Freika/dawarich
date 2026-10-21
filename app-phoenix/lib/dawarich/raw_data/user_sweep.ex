defmodule Dawarich.RawData.UserSweep do
  @moduledoc false

  require Logger

  alias Dawarich.Jobs.Ownership
  alias Dawarich.ReleaseOperations

  @users "SELECT id FROM users WHERE deleted_at IS NULL AND id > $1 ORDER BY id LIMIT 1000"

  def run(repo, oban, key, build, opts) do
    if Keyword.get_lazy(opts, :enabled, fn -> System.get_env("ARCHIVE_RAW_DATA") == "true" end),
      do: sweep(repo, oban, key, build, 0),
      else: disabled(repo, key)
  end

  defp disabled(repo, key) do
    if Ownership.lock(repo, key) == :oban,
      do:
        Logger.warning(
          "#{key} is owned by Oban but ARCHIVE_RAW_DATA is not true in Phoenix, so neither runtime runs it"
        )

    :ok
  end

  defp sweep(repo, oban, key, build, after_id) do
    case Ownership.with_owner(repo, key, :oban, fn -> fan_out(repo, oban, build, after_id) end) do
      {:ok, :done} -> :ok
      {:ok, {:next, last_id}} -> sweep(repo, oban, key, build, last_id)
      {:skip, _owner} -> {:cancel, :not_owner}
    end
  end

  defp fan_out(repo, oban, build, after_id) do
    case ReleaseOperations.ids(repo, @users, [after_id]) do
      [] ->
        :done

      ids ->
        Enum.each(ids, &Oban.insert!(oban, build.(&1)))
        {:next, List.last(ids)}
    end
  end
end
