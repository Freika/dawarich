defmodule Dawarich.Points.Realtime do
  @moduledoc false
  alias Dawarich.Points.{NativeEffects, RealtimeTracksWorker}
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

  defp due(opts, delay),
    do: DateTime.add(Keyword.get_lazy(opts, :now, &DateTime.utc_now/0), delay)
end
