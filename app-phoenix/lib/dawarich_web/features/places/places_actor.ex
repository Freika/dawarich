defmodule DawarichWeb.PlacesActor do
  @moduledoc false
  alias Dawarich.Accounts.Principal

  alias Dawarich.Accounts.Scope
  alias Dawarich.Places.Access

  @fields ~w(id email theme admin status plan active_until subscription_source changelog_consent session_version)a
  @settings ~w(timezone onboarding_completed supporter_email supporter_github_username show_supporter_badge)

  def project(actor) do
    settings = Dawarich.UserSettings.get(actor)
    safe = if is_map(settings), do: Map.take(settings, @settings), else: %{}

    safe =
      case settings do
        %{"family" => %{"location_sharing" => sharing}} when is_map(sharing) ->
          Map.put(safe, "family", %{
            "location_sharing" => Map.take(sharing, ~w(enabled expires_at))
          })

        _ ->
          safe
      end

    struct(Principal, Map.put(Map.take(actor, @fields), :settings, safe))
    |> Map.put(:session_version, Principal.version(actor))
  end

  def tracking_qr(actor, root_url) do
    case Access.admit(Scope.for_user(actor, nil)) do
      {:ok, scope} -> Dawarich.QrSvg.api_key(root_url, scope.user.api_key, 3)
      _ -> ""
    end
  end
end
