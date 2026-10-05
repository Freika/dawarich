defmodule Dawarich.Cache.PreheatDigests do
  @moduledoc false

  alias Dawarich.Digests.Calculation
  alias Dawarich.TimeZoneName

  def call(repo, user_id, opts \\ []) do
    case repo.query!("SELECT id FROM users WHERE id=$1 AND deleted_at IS NULL", [user_id]).rows do
      [] -> :ok
      [[id]] -> preheat(repo, id, opts)
    end
  end

  defp preheat(repo, id, opts) do
    env = Keyword.get(opts, :env, System.get_env())
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    zone = Keyword.get(opts, :ambient_zone, env["TIME_ZONE"] || "Europe/Berlin")
    opts = opts |> Keyword.put(:now, now) |> Keyword.put(:ambient_zone, zone)

    [[year]] =
      repo.query!("SELECT EXTRACT(year FROM ($1::timestamptz AT TIME ZONE $2))::integer", [
        now,
        TimeZoneName.to_iana(zone)
      ]).rows

    years =
      repo.query!(
        "SELECT DISTINCT year FROM stats WHERE user_id=$1 AND year<$2 ORDER BY year DESC LIMIT 2",
        [id, year]
      ).rows

    calculate = Keyword.get(opts, :calculate, &Calculation.yearly/4)
    Enum.each(years, fn [year] -> calculate.(repo, id, year, opts) end)
    :ok
  end
end
