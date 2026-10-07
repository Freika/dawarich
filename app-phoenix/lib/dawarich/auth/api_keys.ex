defmodule Dawarich.Auth.ApiKeys do
  @moduledoc false
  alias Dawarich.Auth.{Account, AccountChanges, Recovery.Token}
  import Ecto.Query
  alias Dawarich.{Accounts, Repo}

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

  def rotate_session(%{"warden.user.user.key" => [[id], salt]} = session)
      when is_integer(id) and is_binary(salt) do
    {:ok, {result, retired}} =
      Repo.transaction(fn ->
        actor =
          Repo.one(
            from u in Account,
              where: u.id == ^id and is_nil(u.deleted_at),
              lock: "FOR UPDATE"
          )

        with %Account{} <- actor,
             %Accounts.User{id: ^id} <- Accounts.from_session(session, DateTime.utc_now()),
             false <- Token.blank?(actor.email),
             true <- Account.normalize_email(actor.email) == actor.email do
          {persist(actor, %{}), actor.api_key}
        else
          _ -> {{:handoff, :invalid_resource}, nil}
        end
      end)

    if match?({:ok, _}, result),
      do: Dawarich.TtlCache.delete({DawarichWeb.RateLimit, retired})

    result
  end

  def rotate_session(_), do: {:handoff, :session}

  defp persist(actor, context) do
    changes = %{
      api_key: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
      updated_at: Map.get(context, :clock, &DateTime.utc_now/0).()
    }

    updated =
      Map.get(context, :repo, Repo).update!(Ecto.Changeset.change(actor, changes), log: false)

    Dawarich.TtlCache.delete({DawarichWeb.RateLimit, actor.api_key})
    {:ok, updated}
  end
end
