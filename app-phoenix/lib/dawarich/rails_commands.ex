defmodule Dawarich.RailsCommands do
  @moduledoc false

  def insert!(repo, kind, %{"user_id" => user_id} = payload)
      when is_binary(kind) and is_integer(user_id) do
    repo.query!(
      "INSERT INTO phoenix.rails_commands (kind, payload) VALUES ($1, $2)",
      [kind, payload],
      log: false
    )

    :ok
  end
end
