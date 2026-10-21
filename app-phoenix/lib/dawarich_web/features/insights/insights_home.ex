defmodule DawarichWeb.InsightsHome do
  @moduledoc "Rails HomeController#index for a signed-in user: redirect to preferred_map_path."
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.RequestURL
  def init(action), do: action
  def call(conn, :index), do: index(conn, conn.params)

  def index(conn, _params) do
    conn
    |> put_resp_header("location", RequestURL.base(conn) <> "/map/v2")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
  end
end
