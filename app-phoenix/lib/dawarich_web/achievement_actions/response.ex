defmodule DawarichWeb.AchievementActions.Response do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.RailsHeaders

  def unlock(conn, status, data \\ nil) do
    conn =
      conn
      |> RailsHeaders.call([])
      |> put_resp_header(
        "cache-control",
        if(status == 200, do: "max-age=0, private, must-revalidate", else: "no-cache")
      )

    {conn, body} =
      if is_nil(data),
        do: {delete_resp_header(conn, "content-type"), ""},
        else: {put_resp_content_type(conn, "application/json"), Jason.encode!(data)}

    conn |> send_resp(status, body) |> halt()
  end

  def terminal(%{state: state} = conn) when state in [:sent, :chunked], do: halt(conn)

  def terminal(conn),
    do: conn |> put_resp_header("cache-control", "no-cache") |> send_resp(500, "") |> halt()

  def json?(conn), do: get_req_header(conn, "accept") == ["application/json"]

  def supported?(conn),
    do:
      json?(conn) or
        (DawarichWeb.Strangler.page_request?(conn) and
           not Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "turbo-stream")))
end
