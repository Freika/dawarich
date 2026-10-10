defmodule Dawarich.Sharing.Commands do
  @moduledoc false
  alias Dawarich.Repo
  alias Dawarich.Sharing.{Resources, Events}
  alias Dawarich.Families.NativeReads
  alias Dawarich.ShareManagement.Mutations

  @actions [:create, :regenerate, :regenerate_phrase, :revoke, :destroy, :update]
  @links [:live, :trip, :track, :timeline, :shared]

  def run(scope, resource, action, attrs, opts) when action in @actions and is_map(attrs) do
    with {:ok, user, _} <- NativeReads.actor(scope, opts),
         :ok <- Resources.admit(resource, user.id),
         :ok <- action(resource, action, attrs) do
      Repo.transaction(fn ->
        Repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [user.id], log: false)

        with {:ok, user, ctx} <- NativeReads.actor(scope, opts),
             :ok <- Resources.access(user, resource, ctx) do
          before = Resources.public_ids(user.id)
          result = invoke(user, resource, action, attrs, ctx, scope.locale, opts)

          case result do
            {:ok, value} ->
              Events.enqueue(Repo, user.id, Enum.uniq(before ++ Resources.public_ids(user.id)))
              {:ok, Resources.sanitize(value)}

            {:invalid, data} ->
              {:error, %{errors: data.errors}}

            {:error, 404} ->
              {:error, :not_found}

            :not_found ->
              {:error, :not_found}

            {:missing, _} ->
              {:error, :not_found}

            {:error, reason} when is_atom(reason) ->
              {:error, reason}

            _ ->
              {:error, :invalid_input}
          end
        end
      end)
      |> case do
        {:ok, result} -> result
        {:error, _} -> {:error, :unavailable}
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def run(_, _, _, _, _), do: {:error, :invalid_input}

  defp action(%{type: type}, action, _) when type in @links do
    if action in [:create, :regenerate, :regenerate_phrase, :revoke, :destroy] and
         (type != :shared or action == :revoke), do: :ok, else: {:error, :invalid_input}
  end

  defp action(%{type: type}, :update, attrs) when type in [:month, :digest, :achievement] do
    valid =
      Enum.all?(attrs, fn {key, value} ->
        key in ~w(enabled expiration) and
          (is_binary(value) or is_boolean(value) or is_number(value))
      end)

    if valid, do: :ok, else: {:error, :invalid_input}
  end

  defp action(_, _, _), do: {:error, :invalid_input}

  defp invoke(user, %{type: type} = resource, action, attrs, ctx, locale, opts)
       when type in @links do
    id = resource[:id]

    Mutations.run(
      user,
      Atom.to_string(type),
      id,
      action,
      attrs,
      locale,
      Keyword.put(opts, :now, ctx.now)
    )
  end

  defp invoke(user, %{type: :month} = resource, :update, attrs, ctx, locale, _) do
    Dawarich.Stats.Sharing.update(
      Repo,
      user,
      resource.year,
      resource.month,
      attrs,
      report_context(ctx, locale)
    )
  end

  defp invoke(user, %{type: :digest} = resource, :update, attrs, ctx, locale, _) do
    Dawarich.Digests.Sharing.update(Repo, user, resource.year, attrs, report_context(ctx, locale))
  end

  defp invoke(user, %{type: :achievement, key: key}, :update, attrs, ctx, _, _) do
    Dawarich.Achievements.Sharing.call(Repo, user.id, key, attrs, %{clock: fn -> ctx.now end})
  end

  defp report_context(ctx, locale), do: Map.merge(ctx, %{locale: locale, base_url: ""})
end
