defmodule DawarichWeb.HomeDispatch do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.{RailsAuth, RailsSession, RequestURL, TrialHomeSession}
  def init(opts), do: opts

  def call(conn, _opts) do
    conn = RailsAuth.call(conn, [])

    conn =
      case conn.assigns.rails_session["flash"] do
        %{} = flash -> RailsSession.stage(conn, %{"flash" => flash})
        _ -> conn
      end

    conn = TrialHomeSession.call(conn, [])
    path = if conn.assigns.current_user, do: "/map/v2", else: "/users/sign_in"

    conn
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
  end
end
