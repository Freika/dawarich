defmodule Dawarich.Users.RecalculationTracks do
  @moduledoc false

  alias Dawarich.Tracks.RangeWorker
  alias Dawarich.Users.RecalculationPeriod, as: Period

  def run(repo, oban, state, args, opts \\ []) do
    Enum.reduce_while(state.years, :ok, fn year, :ok ->
      range = Period.bounds(repo, year, state.zone)

      payload = %{
        "event_id" => Period.event_id(args["source_job_id"], year),
        "user_id" => state.user_id,
        "start_at" => DateTime.to_iso8601(range.start_at),
        "end_at" => DateTime.to_iso8601(range.end_at),
        "time_zone" => state.zone,
        "mode" => "bulk",
        "untracked_only" => false,
        "import_id" => nil,
        "low_priority" => args["job_queue"] == "low_priority"
      }

      Keyword.get(opts, :phase, fn _, _, _ -> :ok end).(:tracks, year, state)

      case RangeWorker.run(repo, oban, payload, Keyword.get(opts, :range_opts, [])) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
