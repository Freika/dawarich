defmodule Dawarich.Tracks.OrphanRuns do
  @moduledoc false

  alias Dawarich.Tracks.{Settings, Sql}

  @owned_sql """
  SELECT p.timestamp, p.track_id FROM points p #{Sql.device_join()}
  WHERE p.user_id = $1 AND #{Sql.device()} = COALESCE($2, '') AND p.track_id IS NOT NULL
    AND p.timestamp BETWEEN $3 AND $4
  ORDER BY p.timestamp
  """

  def call([], _repo, _user), do: []

  def call([first | _] = orphans, repo, user) do
    window = Settings.minutes_between_routes(user) * 60

    params = [
      user.id,
      first.tracker_id,
      first.timestamp - window,
      List.last(orphans).timestamp + window
    ]

    owned = repo.query!(@owned_sql, params, log: false).rows

    orphans
    |> slice_when(&owned_between?(owned, &1.timestamp, &2.timestamp))
    |> Enum.reject(&enclosed?(owned, &1))
  end

  defp slice_when([first | rest], split?) do
    {runs, current, _} =
      Enum.reduce(rest, {[], [first], first}, fn point, {runs, current, prev} ->
        if split?.(prev, point),
          do: {[Enum.reverse(current) | runs], [point], point},
          else: {runs, [point | current], point}
      end)

    Enum.reverse([Enum.reverse(current) | runs])
  end

  defp owned_between?(owned, from, to) do
    case Enum.find(owned, fn [timestamp, _] -> timestamp > from end) do
      [timestamp, _] -> timestamp < to
      nil -> false
    end
  end

  defp enclosed?(owned, run) do
    after_index =
      Enum.find_index(owned, fn [timestamp, _] -> timestamp >= List.last(run).timestamp end)

    before_index =
      (Enum.find_index(owned, fn [timestamp, _] -> timestamp > hd(run).timestamp end) ||
         length(owned)) - 1

    after_index != nil and before_index >= 0 and
      Enum.at(owned, before_index) |> List.last() == Enum.at(owned, after_index) |> List.last()
  end
end
