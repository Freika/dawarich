defmodule Dawarich.Maps.Dependencies.Family do
  @moduledoc false
  alias Dawarich.{Maps, FamilyPage, UserSettings}

  def view(scope, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Maps.with_actor(
      scope,
      fn user ->
        case FamilyPage.read(user, :show,
               now: now,
               self_hosted:
                 Keyword.get(opts, :self_hosted, DawarichWeb.LayoutAssigns.self_hosted?())
             ) do
          {:ok, %{state: :show} = page} ->
            {:ok,
             %{
               presentation: page,
               config: %{
                 "revision" => 1,
                 "range" => %{"timezone" => Dawarich.UserTimeZone.name(UserSettings.get(user))}
               }
             }}

          _ ->
            {:error, :not_found}
        end
      end,
      now: now
    )
  end

  def read(scope, action, params, opts \\ []) when action in [:locations, :history] do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Maps.with_actor(
      scope,
      fn user ->
        case FamilyPage.read(user, :show,
               now: now,
               self_hosted:
                 Keyword.get(opts, :self_hosted, DawarichWeb.LayoutAssigns.self_hosted?())
             ) do
          {:ok, %{state: :show}} ->
            user = Map.put(user, :timezone, Dawarich.UserTimeZone.name(UserSettings.get(user)))

            case action do
              :locations -> Dawarich.Families.Locations.read(user, now)
              :history -> Dawarich.FamilyApi.Closure.run(:history, user, params, now)
            end

          {:redirect, _, :not_in_family} ->
            {:ok, 404, %{error: "not_in_family"}}

          {:redirect, _, :feature_unavailable} ->
            {:ok, 403, %{error: "family_unavailable"}}

          _ ->
            {:error, :unavailable}
        end
      end,
      now: now
    )
  end
end
