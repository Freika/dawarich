defmodule Dawarich.Imports.Providers do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def available(repo, owner) do
    case repo.query!("SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL", [owner],
           log: false
         ).rows do
      [[settings]] ->
        settings = Dawarich.UserSettings.safe(settings)

        for name <- ~w(immich photoprism),
            Ruby.present?(settings[name <> "_url"]) and
              Ruby.present?(settings[name <> "_api_key"]),
            do: name

      _ ->
        []
    end
  end
end
