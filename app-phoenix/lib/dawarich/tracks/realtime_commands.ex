defmodule Dawarich.Tracks.RealtimeCommands do
  @moduledoc false

  alias Dawarich.Tracks.{Owner, RealtimeWorker}
  alias Dawarich.{RailsCommands, State}

  def key(user_id), do: "track_realtime:user:#{user_id}"

  def trigger(repo, user_id, opts \\ []) do
    {:ok, result} =
      repo.transaction(fn ->
        case Owner.lock(repo, "command:tracks.generate_realtime") do
          :oban ->
            if State.debounce(repo, key(user_id), 120) do
              now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
              due = DateTime.add(now, 45)
              payload = %{"user_id" => user_id}

              if opts[:oban] do
                Oban.insert!(opts[:oban], RealtimeWorker.new(payload, scheduled_at: due))
              else
                repo.query!(
                  "INSERT INTO job_outbox(event_id,command_type,command_version,payload,aggregate_id,scheduled_at,metadata) " <>
                    "VALUES($1,'tracks.generate_realtime',1,$2,$3,$4,$5)",
                  [
                    Ecto.UUID.bingenerate(),
                    payload,
                    user_id,
                    due,
                    %{"producer" => "phoenix.tracks.realtime"}
                  ],
                  log: false
                )
              end
            end

          :sidekiq ->
            RailsCommands.insert!(repo, Keyword.get(opts, :kind, "tracks.realtime"), %{
              "user_id" => user_id
            })
        end

        :ok
      end)

    result
  end
end
