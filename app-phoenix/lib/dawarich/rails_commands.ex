defmodule Dawarich.RailsCommands do
  @moduledoc false

  def insert!(repo, kind, %{"user_id" => user_id} = payload)
      when is_binary(kind) and is_integer(user_id),
      do: insert(repo, kind, payload)

  def insert!(
        repo,
        "cache.preheat_sweep",
        %{"time_zone" => zone, "source_job_id" => uuid, "run_at" => at} = payload
      )
      when is_binary(zone) and is_binary(uuid) and byte_size(uuid) == 36 and is_integer(at) and
             map_size(payload) == 3 do
    if match?({:ok, _}, Ecto.UUID.cast(uuid)),
      do: insert(repo, "cache.preheat_sweep", payload),
      else: raise(ArgumentError, "invalid source job UUID")
  end

  defp insert(repo, kind, payload) do
    repo.query!(
      "INSERT INTO phoenix.rails_commands (kind, payload) VALUES ($1, $2::text::jsonb)",
      [kind, Dawarich.RubyJson.encode_exact!(payload)],
      log: false
    )

    :ok
  end
end
