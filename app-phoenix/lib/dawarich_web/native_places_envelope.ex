defmodule DawarichWeb.NativePlacesEnvelope do
  @moduledoc false
  import Plug.Conn

  def prepare(%{method: method, path_info: [path]} = conn)
      when method in ["GET", "HEAD"] and path in ["places", "places.html"] do
    format = Plug.Conn.Query.decode(conn.query_string)["format"]

    formats =
      DawarichWeb.PageAccept.formats(Enum.join(get_req_header(conn, "accept"), ","), false)

    html = formats != :invalid_type and DawarichWeb.PageAccept.negotiate(formats, ["text/html"])

    if format in [nil, "html"] and (format == "html" or html) do
      query =
        conn.query_string
        |> String.split("&", trim: true)
        |> Enum.reject(fn part ->
          part |> String.split("=", parts: 2) |> hd() |> URI.decode_www_form() == "format"
        end)
        |> Enum.join("&")

      conn
      |> put_private(:dawarich_native_places, true)
      |> put_req_header("accept", "text/html")
      |> delete_req_header("turbo-frame")
      |> Map.put(:path_info, ["places"])
      |> Map.put(:request_path, "/places")
      |> Map.put(:query_string, query)
    else
      conn |> put_resp_content_type("text/html") |> send_resp(406, "") |> halt()
    end
  rescue
    Plug.Conn.InvalidQueryError -> conn |> send_resp(400, "") |> halt()
  end

  def prepare(conn), do: DawarichWeb.PageEnvelope.prepare(conn)
end
