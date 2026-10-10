defmodule Dawarich.Families.NativeCommands do
  @moduledoc false

  alias Dawarich.{Families, FamilyPageAccess, Repo}

  alias Dawarich.Families.{NativeReads, WebCreate, NativeCommandDispatch}

  @actions [
    :create,
    :update,
    :delete,
    :invite,
    :cancel_invitation,
    :accept_invitation,
    :remove_member,
    :request_location,
    :respond_location,
    :set_sharing
  ]

  def run(scope, action, attrs, opts) when action in @actions and is_map(attrs) do
    repo = Keyword.get(opts, :repo, Repo)

    with {:ok, _, _} <- NativeReads.actor(scope, opts) do
      repo.transaction(fn ->
        family_id = family_id(repo, scope.user.id, action, attrs)
        lock(repo, family_id, scope.user.id)
        before = members(repo, family_id)

        with {:ok, user, ctx} <- NativeReads.actor(scope, opts),
             :ok <- admit(user, action, ctx, repo),
             {:ok, value} <-
               NativeCommandDispatch.invoke(
                 repo,
                 user,
                 action,
                 attrs,
                 Map.put(ctx, :locale, scope.locale),
                 opts
               )
               |> NativeCommandDispatch.result() do
          family_id = if action in [:create, :accept_invitation], do: value, else: family_id
          recipients = Enum.uniq([user.id | before ++ members(repo, family_id)])
          Families.Events.enqueue(repo, recipients, kind(action))
          Families.Expirations.enqueue(repo, family_id, user.id, recipients, action, value, ctx)
          value
        else
          {:error, reason}
          when action == :accept_invitation and reason in [:family_lapsed, :family_full] ->
            Dawarich.Families.ProducerEvents.family(
              repo,
              family_id,
              :lapse,
              Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
            )

            {:refused, reason}

          {:error, reason} ->
            repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, {:refused, reason}} -> {:error, reason}
        result -> result
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def run(_, _, _, _), do: {:error, :invalid_input}

  defp family_id(repo, _actor, :accept_invitation, %{"token" => token}) when is_binary(token) do
    case repo.query!("SELECT family_id FROM family_invitations WHERE token=$1", [token],
           log: false
         ).rows do
      [[id]] -> id
      [] -> nil
    end
  end

  defp family_id(repo, actor, _, _) do
    case WebCreate.family(repo, actor) do
      nil -> nil
      family -> family.id
    end
  end

  defp lock(repo, family_id, actor) do
    if family_id do
      repo.query!("SELECT id FROM families WHERE id=$1 FOR UPDATE", [family_id], log: false)
    end

    repo.query!(
      "SELECT id FROM users WHERE id=$1 OR id IN (SELECT user_id FROM family_memberships WHERE family_id=$2) ORDER BY id FOR UPDATE",
      [actor, family_id],
      log: false
    )

    repo.query!(
      "SELECT id FROM family_memberships WHERE family_id=$1 ORDER BY id FOR UPDATE",
      [family_id],
      log: false
    )
  end

  defp admit(_user, action, _ctx, _repo)
       when action in [:create, :accept_invitation, :remove_member, :delete, :cancel_invitation],
       do: :ok

  defp admit(user, _action, ctx, repo) do
    case WebCreate.family(repo, user.id) do
      nil ->
        {:error, :unauthorized}

      family ->
        if FamilyPageAccess.available?(user, family, ctx.self_hosted, ctx.now),
          do: :ok,
          else: {:error, :expired}
    end
  end

  defp members(_repo, nil), do: []

  defp members(repo, family),
    do:
      repo.query!("SELECT user_id FROM family_memberships WHERE family_id=$1", [family],
        log: false
      ).rows
      |> List.flatten()

  defp kind(action) when action in [:create, :delete, :accept_invitation, :remove_member],
    do: :membership

  defp kind(action) when action in [:invite, :cancel_invitation], do: :invitation
  defp kind(:set_sharing), do: :consent
  defp kind(:update), do: :membership
  defp kind(_), do: :request
end
