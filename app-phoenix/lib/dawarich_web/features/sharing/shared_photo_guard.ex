defmodule DawarichWeb.SharedPhotoGuard do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.SharedLinks
  alias Dawarich.SharedLinks.FamilyAudience
  alias Dawarich.SharedApi.Closure
  alias DawarichWeb.SharedLinkCookie

  def admit(%{method: method} = conn) when method in ["GET", "HEAD"] do
    case conn.private[:dawarich_original_path_info] || conn.path_info do
      ["api", "v1", "shared", id, "photos", photo, action] ->
        if String.split(action, ".", parts: 2) |> hd() == "thumbnail",
          do: check(conn, URI.decode(id), URI.decode(photo)),
          else: conn

      _ ->
        conn
    end
  end

  def admit(conn), do: conn

  defp check(conn, id, photo) do
    now = conn.assigns[:api_now] || DateTime.utc_now()

    with true <- SharedLinks.api_uuid?(id),
         %{settings: %{"show_photos" => true}} = link <- SharedLinks.active(id, now),
         true <- FamilyAudience.family_only?(link) or SharedLinkCookie.unlocked?(conn, link, now) do
      params = conn.assigns[:api_params] || fetch_query_params(conn).query_params
      source = params["source"]

      if is_binary(source) and Closure.allowed_photo?(link, source, photo),
        do: conn,
        else: deny(conn)
    else
      _ -> conn
    end
  rescue
    _ -> deny(conn)
  end

  defp deny(conn),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("cache-control", "no-cache")
      |> send_resp(404, "")
      |> halt()
end
