defmodule DawarichWeb.BrowserMapPhotos do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Photos.Index
  alias DawarichWeb.Api.Respond

  def call(conn) do
    params = conn.assigns.api_params

    case Index.fetch(conn.assigns.api_user, params) do
      {:ok, photos, errors} ->
        page = String.to_integer(params["page"])
        per = String.to_integer(params["per_page"])
        conn = put_resp_header(conn, "x-total-pages", to_string(ceil(length(photos) / per)))

        conn =
          if errors == [],
            do: conn,
            else: put_resp_header(conn, "x-photo-source-errors", Enum.join(errors, ","))

        Respond.json(conn, 200, photos |> Enum.slice((page - 1) * per, per) |> Index.term())

      {:unconfigured, source} ->
        {:ok, message} =
          Dawarich.I18n.t(
            "en",
            "controllers.api.v1.photos.capitalize_integration_not_configured",
            %{"source" => source && String.capitalize(source)}
          )

        Respond.json(conn, 401, %{error: message, code: "photos_unconfigured"})

      {:error, _} ->
        Respond.json(conn, 502, %{
          error: Dawarich.I18n.en!("controllers.api.v1.photos.failed_to_fetch_photos")
        })
    end
  end
end
