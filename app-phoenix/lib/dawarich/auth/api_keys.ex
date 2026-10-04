defmodule Dawarich.Auth.ApiKeys do
  @moduledoc false
  alias Dawarich.Auth.{AccountChanges, Recovery.Token}
  alias Dawarich.Repo

  def rotate(id, session_salt, context) do
    with {:ok, actor} <- AccountChanges.actor(id, session_salt, context),
         false <- Token.blank?(actor.email) do
      changes = %{
        api_key: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
        updated_at: Map.get(context, :clock, &DateTime.utc_now/0).()
      }

      {:ok, Map.get(context, :repo, Repo).update!(Ecto.Changeset.change(actor, changes))}
    else
      true -> {:handoff, :invalid_resource}
      handoff -> handoff
    end
  end
end
