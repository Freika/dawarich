defmodule DawarichWeb.VisitSettingsActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Jobs, Visits.WebSettings}
  alias DawarichWeb.{Locale, RailsSession, RequestURL, Translate}
  alias DawarichWeb.Api.Body

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, :update) do
    user = conn.assigns.current_user

    case WebSettings.save(
           Jobs.repo(),
           user.id,
           conn.assigns.api_params["settings"],
           DateTime.utc_now()
         ) do
      {:ok, _} -> redirect(conn, "controllers.settings.visits.visit_detection_settings_updated")
      {:replay, reason} -> Body.replay(conn, reason)
    end
  end

  def call(conn, :redetect) do
    user = conn.assigns.current_user
    locale = Locale.resolve(nil, user, conn.assigns.rails_session)

    case WebSettings.redetect(Jobs.repo(), user.id, DateTime.utc_now(), locale) do
      {:ok, _} ->
        redirect(
          conn,
          "controllers.visits.redetections.re_detection_queued_we_ll_notify_you_when_it_finishes"
        )

      {:cooldown, 429} ->
        Body.replay(conn, "visit redetection cooldown flash")

      {:replay, reason} ->
        Body.replay(conn, reason)
    end
  end

  defp redirect(conn, key) do
    locale = Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)
    notice = Translate.t(locale, key, %{})

    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{"notice" => notice}}})
    |> put_resp_header("location", RequestURL.base(conn) <> "/settings/visits")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end
end
