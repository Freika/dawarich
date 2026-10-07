defmodule Dawarich.Visits.WebScope do
  @moduledoc false
  alias Dawarich.{Entitlements, Repo, RubyInteger, TimeZoneName, UserTimeZone}
  alias Dawarich.Timeline.Sql
  @active "v.user_id=$1 AND v.deleted_at IS NULL AND v.status<>2"

  def ids(raw, limit \\ 500)
  def ids(nil, _limit), do: {:ok, []}
  def ids(raw, limit) when is_binary(raw), do: ids([raw], limit)

  def ids(raw, limit) when is_list(raw) do
    if Enum.all?(raw, &(is_binary(&1) and String.valid?(&1))) do
      parsed = raw |> Enum.map(&RubyInteger.to_i/1) |> Enum.reject(&(&1 == 0)) |> Enum.uniq()

      if is_integer(limit) and length(parsed) > limit,
        do: {:error, :too_many},
        else: {:ok, parsed}
    else
      {:replay, "visit selection shape"}
    end
  end

  def ids(_raw, _limit), do: {:replay, "visit selection shape"}

  def load(repo, user, ids, now, self_hosted) do
    with {:ok, cutoff} <- cutoff(repo, user, now, self_hosted) do
      %{columns: columns, rows: raw} =
        repo.query!(
          "SELECT v.* FROM visits v WHERE #{@active} AND v.id=ANY($2) AND ($3::timestamp IS NULL OR v.started_at >= $3) ORDER BY v.id FOR UPDATE",
          [user.id, ids, cutoff],
          log: false
        )

      rows = Enum.map(raw, &Map.new(Enum.zip(columns, &1)))
      if length(rows) == length(ids), do: {:ok, rows}, else: missing(repo, user.id, ids, cutoff)
    end
  end

  def cutoff(repo, user, now, self_hosted) do
    if Entitlements.full_access?(repo, user, self_hosted, now) do
      {:ok, nil}
    else
      with {:ok, zone} <- zone(repo, Dawarich.UserSettings.get(user)) do
        [[at]] =
          UserTimeZone.query!(
            "SELECT #{Sql.window_start("$1")} AT TIME ZONE 'UTC' FROM z",
            [now],
            %{"timezone" => zone},
            repo
          ).rows

        {:ok, at}
      end
    end
  end

  def day_bounds(zone, date, repo \\ Repo)

  def day_bounds(zone, date, repo) when is_binary(zone) and is_binary(date) do
    with {:ok, day} <- Date.from_iso8601(date),
         {:ok, zone} <- known_zone(repo, zone) do
      [[start, stop]] =
        repo.query!(
          "SELECT ($1::date::timestamp AT TIME ZONE $2) AT TIME ZONE 'UTC', (($1::date + 1)::timestamp AT TIME ZONE $2) AT TIME ZONE 'UTC'",
          [day, zone],
          log: false
        ).rows

      {:ok, {start, stop}}
    else
      _ -> {:replay, "visit date or time zone"}
    end
  end

  def day_bounds(_zone, _date, _repo), do: {:replay, "visit date or time zone"}

  defp missing(_repo, _user_id, _ids, nil), do: {:error, :missing}

  defp missing(repo, user_id, ids, cutoff) do
    [[archived]] =
      repo.query!(
        "SELECT EXISTS(SELECT 1 FROM visits WHERE user_id=$1 AND id=ANY($2) AND started_at<$3)",
        [user_id, ids, cutoff],
        log: false
      ).rows

    {:error, if(archived, do: :archived, else: :missing)}
  end

  def zone(repo, %{"timezone" => zone}) when is_binary(zone),
    do: known_zone(repo, if(zone == "", do: "UTC", else: zone))

  def zone(repo, %{} = settings) when not is_map_key(settings, "timezone"),
    do: known_zone(repo, UserTimeZone.zone(settings, System.get_env()))

  def zone(repo, %{"timezone" => nil}),
    do: known_zone(repo, UserTimeZone.zone(%{}, System.get_env()))

  def zone(_repo, _settings), do: {:replay, "visit time zone shape"}

  defp known_zone(repo, name) do
    zone = TimeZoneName.to_iana(name)

    case repo.query!("SELECT name FROM pg_timezone_names WHERE name=$1", [zone], log: false).rows do
      [[^zone]] -> {:ok, zone}
      [] -> {:replay, "unknown visit time zone"}
    end
  end
end
