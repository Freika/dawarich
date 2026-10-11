defmodule DawarichWeb.Api.SettingsController do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Settings.{Api, Progress}
  alias DawarichWeb.Api.Respond

  def init(action) do
    action
  end

  def call(conn, :general) do
    general(conn)
  end

  def call(conn, action) do
    ctx = Api.context(conn)
    user = conn.assigns.api_user

    result =
      case action do
        :index -> Api.index(Dawarich.Repo, user, ctx)
        :settings -> Api.index(Dawarich.Repo, user, ctx)
        :update -> Api.update(Dawarich.Repo, user, conn.assigns.api_params, ctx)
        :transportation_recalculation_status -> Progress.show(user, ctx)
        :progress -> Progress.show(user, ctx)
      end

    {_, status, body} = result
    Respond.json(conn, status, Api.term(body))
  rescue
    _ -> Respond.json(conn, 500, Api.failure())
  end

  defp general(conn) do
    params = conn.assigns.api_params
    check = assign(conn, :api_params, Map.delete(params, "locale"))

    with :ok <- DawarichWeb.RailsForm.admission(check, allowed_overrides: ["PATCH"]),
         {:ok, settings} <-
           Api.general(Dawarich.Repo, conn.assigns.current_user, params, Api.context(conn)) do
      locale = settings["locale"] || "en"

      notice =
        DawarichWeb.Translate.t(locale, "controllers.settings.general.settings_updated", %{})

      conn
      |> DawarichWeb.RailsSession.stage(%{
        "flash" => %{"discard" => [], "flashes" => %{"notice" => notice}}
      })
      |> put_resp_header("location", DawarichWeb.RequestURL.base(conn) <> "/settings/general")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_content_type("text/html")
      |> send_resp(302, "")
      |> halt()
    else
      _ -> DawarichWeb.StandaloneError.respond(conn, "settings_general_failure", 422)
    end
  end

  defdelegate permit(arg1, arg2), to: Dawarich.Settings.Input
  defdelegate term(arg1), to: Dawarich.Settings.Input
  defdelegate scalars(arg1, arg2), to: Dawarich.Settings.Input
  defdelegate valid_tiles?(arg1), to: Dawarich.Settings.Input
end
