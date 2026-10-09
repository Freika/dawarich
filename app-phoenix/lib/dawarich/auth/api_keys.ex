defmodule Dawarich.Auth.ApiKeys do
  @moduledoc false
  alias Dawarich.Auth.{Account, AccountChanges, Recovery.Token}
  alias Dawarich.Repo

  def rotate(id, session_salt, context) do
    module = if context[:native], do: Dawarich.Auth.AccountClosure, else: AccountChanges

    with {:ok, actor} <- module.actor(id, session_salt, context),
         false <- Token.blank?(actor.email),
         true <- Account.normalize_email(actor.email) == actor.email do
      persist(actor, context)
    else
      value when is_boolean(value) -> {:handoff, :invalid_resource}
      handoff -> handoff
    end
  end

  defp persist(actor, context) do
    changes = %{
      api_key: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
      updated_at: Map.get(context, :clock, &DateTime.utc_now/0).()
    }

    repo = Map.get(context, :repo, Repo)

    {:ok, updated} =
      repo.transaction(fn ->
        updated =
          Map.get(context, :repo, Repo).update!(Ecto.Changeset.change(actor, changes), log: false)

        if is_binary(actor.api_key) do
          Dawarich.AfterCommit.cache(Map.get(context, :repo, Repo), "rate_limit", %{
            "user_id" => actor.id,
            "key_hash" => Base.encode16(:crypto.hash(:sha256, actor.api_key), case: :lower)
          })
        end

        updated
      end)

    {:ok, updated}
  end
end
