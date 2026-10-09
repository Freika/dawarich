defmodule DawarichWeb.SettingsSupporterActions do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.{Repo, Settings.Supporter}
  alias DawarichWeb.SettingsActions
  def init(action), do: action

  def call(conn, :verify) do
    case SettingsActions.admit(conn, ["POST"]) do
      :ok ->
        case Supporter.verify(Repo, conn.assigns.current_user.id, conn.assigns.api_params) do
          {:ok, %{"supporter" => true} = info} ->
            platform = DawarichWeb.SettingsLive.GeneralHelpers.platform_name(info["platform"])

            SettingsActions.redirect(
              conn,
              "/settings/general",
              "verified_thank_you_for_supporting_dawarich_via_platform",
              "notice",
              %{platform: platform}
            )

          {:ok, _} ->
            SettingsActions.redirect(
              conn,
              "/settings/general",
              "not_found_in_supporter_list_make_sure_you_re_using",
              "alert"
            )

          {:error, :empty} ->
            SettingsActions.redirect(
              conn,
              "/settings/general",
              "please_enter_an_email_address_or_github_username",
              "alert"
            )

          {:error, _} ->
            SettingsActions.reject(conn, 500)
        end

      {:error, status} ->
        SettingsActions.reject(conn, status)
    end
  rescue
    _ -> SettingsActions.reject(conn, 500)
  end
end
