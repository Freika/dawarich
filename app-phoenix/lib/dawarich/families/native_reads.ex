defmodule Dawarich.Families.NativeReads do
  @moduledoc false

  alias Dawarich.{Accounts, FamilyPage, FamilyPageAccess, UserSettings}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Families.{History, Locations, NativeDeadline, Snapshot, WebCreate}

  def actor(%Scope{user: %{id: id} = original}, opts) do
    repo = Keyword.get(opts, :repo, Dawarich.Repo)
    user = repo.get(Dawarich.Accounts.User, id, log: false)

    user =
      if user && is_nil(user.deleted_at) && Accounts.unlocked?(user, DateTime.utc_now()), do: user

    if user && Dawarich.Accounts.Principal.same_identity?(original, user) do
      {:ok, user, context(opts)}
    else
      {:error, :stale_session}
    end
  end

  def actor(_, _), do: {:error, :stale_session}

  def context(opts) do
    %{
      now:
        Keyword.get(opts, :clock, fn -> Keyword.get_lazy(opts, :now, &DateTime.utc_now/0) end).(),
      self_hosted: Keyword.get_lazy(opts, :self_hosted, &Dawarich.ReleaseMigration.self_hosted?/0)
    }
  end

  def page(scope, action, opts) do
    with :ok <- action(action),
         {:ok, user, ctx} <- actor(scope, opts) do
      user |> FamilyPage.read(action, Keyword.merge(opts, Map.to_list(ctx))) |> result()
    end
  rescue
    ArgumentError -> {:error, :invalid_input}
  end

  def locations(scope, opts) do
    with {:ok, user, ctx} <- admitted(scope, opts) do
      Snapshot.read(user, Keyword.merge(opts, Map.to_list(ctx)), fn ->
        with {:ok, 200, {:object, fields}} <-
               Keyword.get(opts, :location_reader, &Locations.read/2).(project(user), ctx.now),
             deadline <- NativeDeadline.due(ctx.family, user, ctx) do
          fields = object({:object, fields})

          {:ok,
           %{
             locations: Enum.sort_by(fields["locations"], & &1["email"]),
             sharing_enabled: fields["sharing_enabled"],
             updated_at: fields["updated_at"],
             deadline: deadline
           }}
        else
          {:error, _} = error -> error
          _ -> {:error, :unavailable}
        end
      end)
    end
  rescue
    ArgumentError -> {:error, :invalid_input}
  end

  def history(scope, params, opts) when is_map(params) do
    with {:ok, user, ctx} <- admitted(scope, opts) do
      Snapshot.read(user, Keyword.merge(opts, Map.to_list(ctx)), fn ->
        with {:ok, 200, fields} <-
               Keyword.get(opts, :history_reader, &History.read/3).(
                 project(user),
                 params,
                 ctx.now
               ) do
          {:ok, object(fields)}
        else
          {:error, _} = error -> error
          _ -> {:error, :invalid_input}
        end
      end)
    end
  rescue
    ArgumentError -> {:error, :invalid_input}
  end

  def history(_, _, _), do: {:error, :invalid_input}

  def admitted(scope, opts) do
    with {:ok, user, ctx} <- actor(scope, opts),
         family when not is_nil(family) <- WebCreate.family(Dawarich.Repo, user.id),
         true <- FamilyPageAccess.available?(user, family, ctx.self_hosted, ctx.now) do
      {:ok, user, Map.put(ctx, :family, family)}
    else
      {:error, _} = error -> error
      nil -> {:error, :unauthorized}
      false -> {:error, :expired}
    end
  end

  defp result({:ok, page}) do
    invitations = Enum.map(Map.get(page, :invitations, []), &Map.delete(&1, :token))
    {:ok, Map.put(page, :invitations, invitations)}
  end

  defp result({:redirect, _, :feature_unavailable}), do: {:error, :expired}
  defp result({:redirect, _, _}), do: {:error, :unauthorized}
  defp result({:error, 404}), do: {:error, :not_found}
  defp result({:error, _} = error), do: error
  defp result(:rails), do: {:error, :invalid_input}

  defp action(action) when action in [:show, :new, :edit, :invitations], do: :ok
  defp action({:request, id}) when is_integer(id) and id > 0, do: :ok
  defp action(_), do: {:error, :invalid_input}

  defp project(user), do: Map.put(user, :timezone, UserSettings.get(user)["timezone"])
  defp object({:object, fields}), do: Map.new(fields, fn {key, value} -> {key, object(value)} end)
  defp object(list) when is_list(list), do: Enum.map(list, &object/1)
  defp object(value), do: value
end
