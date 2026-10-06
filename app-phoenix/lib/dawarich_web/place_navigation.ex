defmodule DawarichWeb.PlaceNavigation do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Repo
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.{MapFrames, NearbyPlaces, RequestURL}

  def init(action), do: action

  def call(conn, :show) do
    id = String.to_integer(conn.path_params["id"])

    case Repo.query!(
           "SELECT id FROM places WHERE id=$1 AND user_id=$2",
           [id, conn.assigns.current_user.id],
           log: false
         ).rows do
      [[^id]] ->
        if get_req_header(conn, "turbo-frame") == ["place-drawer"] do
          MapFrames.call(conn, :place)
        else
          conn
          |> put_resp_header("location", RequestURL.base(conn) <> "/map/v2?place_id=#{id}")
          |> put_resp_header("cache-control", "no-cache")
          |> put_resp_content_type("text/html")
          |> send_resp(302, "")
          |> halt()
        end

      [] ->
        html = DawarichWeb.ErrorHTML.render("404.html", %{}) |> Phoenix.HTML.Safe.to_iodata()
        conn |> put_resp_content_type("text/html", "UTF-8") |> send_resp(404, html) |> halt()
    end
  end

  def call(conn, :nearby) do
    case nearby_state(conn.query_params) do
      {:ok, 400, _} ->
        conn |> send_resp(400, "") |> halt()

      {:ok, 200, radius} ->
        html =
          NearbyPlaces.render(%{
            __changed__: nil,
            locale: conn.assigns.locale,
            params: conn.query_params,
            places:
              Dawarich.Places.Nearby.fetch(
                conn.assigns.current_user,
                Ruby.to_f(conn.query_params["latitude"]),
                Ruby.to_f(conn.query_params["longitude"]),
                radius,
                if(conn.query_params["limit"],
                  do: DawarichWeb.Params.ruby_to_i(conn.query_params["limit"]),
                  else: 5
                )
              ),
            radius: radius
          })
          |> Phoenix.HTML.Safe.to_iodata()

        conn
        |> put_resp_header("vary", "Accept")
        |> put_resp_header("cache-control", "max-age=0, private, must-revalidate")
        |> put_resp_content_type("text/html")
        |> send_resp(200, html)
        |> halt()
    end
  end

  def nearby_state(params) do
    if Ruby.blank?(params["latitude"]) or Ruby.blank?(params["longitude"]) do
      {:ok, 400, nil}
    else
      radius = if params["radius"], do: Ruby.to_f(params["radius"]), else: 0.5
      {:ok, 200, radius}
    end
  end
end
