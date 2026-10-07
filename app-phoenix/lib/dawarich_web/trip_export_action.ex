defmodule DawarichWeb.TripExportAction do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.{Jobs, PointExports, Trips.WebExport}
  alias DawarichWeb.{Locale, RailsSession, RequestURL, Translate, TripActions}

  def call(conn) do
    user = conn.assigns.current_user
    id = String.to_integer(conn.path_params["id"])
    locale = Locale.resolve(nil, user, conn.assigns.rails_session)

    case WebExport.prepare(Jobs.repo(), user, id, conn.assigns.api_params["file_format"], %{}) do
      {:ok, export} ->
        case PointExports.create(export, user, locale, Jobs.repo()) do
          {:ok, _} ->
            TripActions.redirect(
              conn,
              302,
              "/exports",
              Translate.t(
                locale,
                "controllers.trips.trip_export_initiated_check_the_exports_page_when_it_s",
                %{}
              )
            )

          {:error, _} ->
            error(conn, id, locale, "export_failed_to_initiate_please_try_again")
        end

      {:invalid, :format} ->
        error(conn, id, locale, "unsupported_export_format_choose_gpx_or_geojson")

      {:replay, reason} ->
        DawarichWeb.TripRequest.replay(conn, reason)

      {:error, :not_found} ->
        TripActions.not_found(conn)
    end
  end

  defp error(conn, id, locale, key) do
    conn
    |> RailsSession.put(%{
      "flash" => %{
        "discard" => [],
        "flashes" => %{"alert" => Translate.t(locale, "controllers.trips.#{key}", %{})}
      }
    })
    |> put_resp_header("location", RequestURL.base(conn) <> "/trips/#{id}")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(422, "")
    |> halt()
  end
end
