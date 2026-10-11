defmodule Dawarich.Maps do
  @moduledoc false
  alias Dawarich.Accounts.Scope
  alias Dawarich.Maps.Projection
  alias Dawarich.Accounts.{DataAccess, Principal}

  def principal(user, locale), do: Scope.for_user(Principal.project(user), locale)

  def admit(scope, opts \\ []) do
    with {:ok, fresh} <- actor(scope, opts) do
      {:ok, %{fresh | user: Principal.project(fresh.user)}}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def with_actor(scope, effect, opts \\ []) do
    with {:ok, fresh} <- actor(scope, opts), do: effect.(fresh.user)
  rescue
    _ -> {:error, :unavailable}
  end

  defp actor(scope, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with {:ok, fresh} <- DataAccess.admit(scope, opts) do
      user = fresh.user

      if user.status in [0, 3] or
           (user.active_until && DateTime.compare(user.active_until, now) == :lt),
         do: {:error, :unauthorized},
         else: {:ok, fresh}
    end
  end

  def page(scope, params, opts) when is_map(params) do
    with_actor(
      scope,
      fn user ->
        case Dawarich.MapPage.load(user, params, opts) do
          {:ok, page} -> {:ok, Projection.page(page)}
          :not_found -> {:error, :not_found}
        end
      end,
      opts
    )
  end

  def page(_, _, _), do: {:error, :invalid}
end
