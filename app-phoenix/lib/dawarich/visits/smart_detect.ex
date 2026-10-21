defmodule Dawarich.Visits.SmartDetect do
  @moduledoc false

  alias Dawarich.Visits.{Calendar, Runner, Settings}

  @none %{visits: [], skipped_ranges: []}

  def run(repo, user_id, start, stop, %{"time_zone" => zone} = args) do
    start = if args["plan_restricted"], do: max(start, Calendar.year_ago(repo, zone)), else: start

    with %{} = user <- Settings.load(repo, user_id),
         true <- start < stop,
         true <- points?(repo, user_id, start, stop) do
      {visits, skipped} = Runner.run(repo, user, start, stop, zone)
      %{visits: visits, skipped_ranges: skipped}
    else
      _ -> @none
    end
  end

  defp points?(repo, user_id, start, stop),
    do:
      repo.query!(
        "SELECT EXISTS (SELECT 1 FROM points WHERE user_id = $1 AND (anomaly = false OR anomaly IS NULL) " <>
          "AND timestamp BETWEEN $2 AND $3)",
        [user_id, start, stop],
        log: false
      ).rows == [[true]]
end
