defmodule Dawarich.RailsCommands do
  @moduledoc false

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
