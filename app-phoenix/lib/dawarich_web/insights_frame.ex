defmodule DawarichWeb.InsightsFrame do
  @moduledoc "Details-only browser pipeline adapter; direct requests retain the app root layout."
  @behaviour Plug
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _opts) do
    frame = conn |> get_req_header("turbo-frame") |> Enum.join(", ") |> String.trim() != ""

    conn =
      conn
      |> put_private(:insights_frame, frame)
      |> put_resp_header("cache-control", "max-age=0, private, must-revalidate")

    conn =
      if conn.request_path == "/insights/details" and
           conn |> get_req_header("accept") |> Enum.any?(&(String.trim(&1) != "")),
         do: put_resp_header(conn, "vary", "Accept"),
         else: conn

    if frame,
      do: Phoenix.Controller.put_root_layout(conn, {DawarichWeb.InsightsFrameLayout, :render}),
      else: conn
  end

  def live_session(conn),
    do:
      Map.put(
        DawarichWeb.RailsAuth.live_session(conn),
        "insights_frame",
        conn.private[:insights_frame] == true
      )
end
