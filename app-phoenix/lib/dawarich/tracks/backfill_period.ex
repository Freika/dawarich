defmodule Dawarich.Tracks.BackfillPeriod do
  @moduledoc false

  def payload(repo, user_id, earliest, latest, zone, now) do
    zone = Dawarich.TimeZoneName.to_iana(zone)

    [[from, until]] =
      repo.query!(
        """
        SELECT (date_trunc('day', to_timestamp($1) AT TIME ZONE $3) AT TIME ZONE $3) AT TIME ZONE 'UTC',
          LEAST(((date_trunc('day', to_timestamp($2) AT TIME ZONE $3) + interval '1 day')
            AT TIME ZONE $3) - interval '1 microsecond', $4::timestamptz - interval '6 hours') AT TIME ZONE 'UTC'
        """,
        [earliest, latest, zone, now],
        log: false
      ).rows

    %{
      "user_id" => user_id,
      "start_at" => iso(from),
      "end_at" => iso(until),
      "time_zone" => zone,
      "mode" => "bulk",
      "untracked_only" => true,
      "import_id" => nil,
      "low_priority" => false
    }
  end

  defp iso(at),
    do:
      at
      |> Map.put(:microsecond, {elem(at.microsecond, 0), 6})
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.to_iso8601()
end
