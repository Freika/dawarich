defmodule Dawarich.Auth.ApiKeys do
  @moduledoc false
  alias Dawarich.Auth.{Account, AccountChanges, Recovery.Token}
  alias Dawarich.Repo

  def rotate(id, session_salt, context) do
    module = if context[:native], do: Dawarich.Auth.AccountClosure, else: AccountChanges

    with {:ok, actor} <- module.actor(id, session_salt, context),
         false <- Token.blank?(actor.email),
         true <- Account.normalize_email(actor.email) == actor.email do
      changes = %{
        api_key: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
        updated_at: Map.get(context, :clock, &DateTime.utc_now/0).()
      }

      updated =
        Map.get(context, :repo, Repo).update!(Ecto.Changeset.change(actor, changes), log: false)

      Dawarich.TtlCache.delete({DawarichWeb.RateLimit, actor.api_key})
      {:ok, updated}
    else
      value when is_boolean(value) -> {:handoff, :invalid_resource}
      handoff -> handoff
    end
  end
end
