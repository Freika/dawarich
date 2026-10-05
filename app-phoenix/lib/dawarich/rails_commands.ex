defmodule Dawarich.RailsCommands do
  @moduledoc false

  def insert!(
        repo,
        "release_achievements_bulk_check" = kind,
        %{
          "job_id" => job_id,
          "options" => %{"notify" => notify, "force" => force, "stale_only" => stale} = options,
          "run_at" => run_at
        } = payload
      )
      when map_size(payload) == 3 and map_size(options) == 3 and is_binary(job_id) and
             is_binary(run_at) and is_boolean(notify) and is_boolean(force) and is_boolean(stale) do
    with {:ok, _} <- Ecto.UUID.cast(job_id),
         {:ok, _, _} <- DateTime.from_iso8601(run_at) do
      insert_row!(repo, kind, payload)
    else
      _ -> raise ArgumentError, "invalid release bulk payload"
    end
  end

  def insert!(_repo, "release_achievements_bulk_check", _payload),
    do: raise(ArgumentError, "invalid release bulk payload")

  def insert!(repo, kind, %{"user_id" => user_id} = payload)
      when is_binary(kind) and is_integer(user_id) do
    insert_row!(repo, kind, payload)
  end

  def insert!(repo, "places_bulk_name_fetch" = kind, payload)
      when is_map(payload) and map_size(payload) == 0 do
    insert_row!(repo, kind, payload)
  end

  defp insert_row!(repo, kind, payload) do
    repo.query!(
      "INSERT INTO phoenix.rails_commands (kind, payload) VALUES ($1, $2::text::jsonb)",
      [kind, Dawarich.RubyJson.encode_exact!(payload)],
      log: false
    )

    :ok
  end
end
