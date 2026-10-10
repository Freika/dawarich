defmodule Dawarich.Maps do
  @moduledoc false
  alias Dawarich.Accounts.Scope
  alias Dawarich.Maps.{Projection, Dependencies.Principal}

  def principal(user, locale), do: Principal.scope(user, locale)

  def admit(scope, opts \\ []) do
    with {:ok, user} <- Principal.actor(scope, Keyword.get(opts, :now, DateTime.utc_now())) do
      {:ok,
       %Scope{
         scope
         | user: Map.put(Principal.safe(user), :session_identity, scope.user.session_identity)
       }}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def with_actor(scope, effect, opts \\ []) do
    with {:ok, user} <- Principal.actor(scope, Keyword.get(opts, :now, DateTime.utc_now())) do
      effect.(user)
    end
  rescue
    _ -> {:error, :unavailable}
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
