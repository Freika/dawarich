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

  def command(scope, action, params, opts \\ []) do
    now = DateTime.utc_now()
    ctx = %{now: now, locale: scope.locale, self_hosted: Keyword.get(opts, :self_hosted, true)}

    Maps.with_actor(scope, fn actor ->
      user =
        actor
        |> Map.put(:timezone, Dawarich.UserTimeZone.name(UserSettings.get(actor)))
        |> Map.put(:locale, scope.locale)

      case action do
        "sharing" ->
          Dawarich.Families.SharingUpdate.web_call(
            user,
            Map.take(params, ~w(enabled duration share_history history_window)),
            now
          )

        "member" ->
          Dawarich.Families.WebMemberships.run(Dawarich.Repo, user, integer(params["id"]), ctx)

        "destroy" ->
          Dawarich.Families.WebDestroy.run(Dawarich.Repo, user, ctx)

        "invite" ->
          Dawarich.Families.WebInvitations.create(
            Dawarich.Repo,
            user,
            Map.take(params, ["email"]),
            ctx
          )

        "cancel" ->
          Dawarich.Families.WebInvitations.cancel(Dawarich.Repo, user, params["token"], ctx)

        "request" ->
          Dawarich.Families.Requests.web_create(user, %{"target_user_id" => params["id"]}, now)

        _ ->
          {:error, :invalid}
      end
    end)
  end

  defp integer(value) when is_binary(value) and byte_size(value) <= 19 do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 -> id
      _ -> 0
    end
  end

  defp integer(_), do: 0

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
