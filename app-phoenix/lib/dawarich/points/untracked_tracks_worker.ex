defmodule Dawarich.Points.UntrackedTracksWorker do
  @moduledoc false
  use Oban.Worker, queue: :tracks, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}), do: run(Dawarich.Jobs.repo(), conf.name, args)

  def run(repo, oban, %{"user_id" => user, "import_id" => import, "event_id" => event}) do
    case repo.query!(
           "SELECT count(p.id),min(p.timestamp),max(p.timestamp),u.settings FROM imports i JOIN users u ON u.id=i.user_id LEFT JOIN points p ON p.import_id=i.id WHERE i.id=$1 AND i.user_id=$2 GROUP BY u.settings",
           [import, user],
           log: false
         ).rows do
      [[count, first, last, settings]] when count >= 2 and not is_nil(first) ->
        payload = %{
          "user_id" => user,
          "start_at" => iso(first),
          "end_at" => iso(last),
          "time_zone" => Dawarich.UserTimeZone.iana(repo, settings),
          "mode" => "bulk",
          "untracked_only" => true,
          "import_id" => import,
          "low_priority" => false,
          "event_id" => event
        }

        Dawarich.Tracks.RangeWorker.run(repo, oban, payload)

      _ ->
        :ok
    end
  end

  defp iso(at), do: at |> DateTime.from_unix!() |> DateTime.to_iso8601()
end
