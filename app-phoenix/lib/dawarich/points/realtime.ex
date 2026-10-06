defmodule Dawarich.Points.Realtime do
  @moduledoc false
  alias Dawarich.Points.{NativeEffects, RealtimeTracksWorker, RealtimeVisitsWorker}
  alias Dawarich.{RailsCommands, State}

  def tracks(repo, payload, opts \\ []) do
    if NativeEffects.native?(repo, "command:tracks.generate_realtime") do
      if State.debounce(repo, "track_realtime:user:#{payload["user_id"]}", 120),
        do:
          NativeEffects.enqueue(repo, RealtimeTracksWorker, payload, scheduled_at: due(opts, 45))

      :ok
    else
      RailsCommands.insert!(repo, "tracks.realtime", payload)
    end
  end

  def visits(repo, %{"user_id" => user} = payload, opts \\ []) do
    if NativeEffects.native?(repo, "command:visits.suggest") do
      case Dawarich.Visits.Settings.load(repo, user) do
        nil ->
          :ok

        actor ->
          if Dawarich.Geocoding.Config.resolve(repo).enabled and
               Dawarich.Visits.Settings.policy(actor.settings).suggestions_enabled and
               State.debounce(repo, "visit_realtime:user:#{user}", 600) do
            now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0) |> DateTime.to_unix()

            args = %{
              "user_id" => user,
              "start_at" => now - 21_600,
              "end_at" => now,
              "time_zone" => Dawarich.UserTimeZone.iana(repo, actor.settings),
              "stepping" => "fixed",
              "plan_restricted" => true
            }

            NativeEffects.enqueue(repo, RealtimeVisitsWorker, args, scheduled_at: due(opts, 300))
          end

          :ok
      end
    else
      RailsCommands.insert!(repo, "visits.realtime", payload)
    end
  end

  defp due(opts, delay),
    do: DateTime.add(Keyword.get_lazy(opts, :now, &DateTime.utc_now/0), delay)
end
