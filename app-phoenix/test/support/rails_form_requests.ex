defmodule Dawarich.Test.RailsFormRequests do
  @moduledoc false

  import Dawarich.Test.RawHTTP
  import Phoenix.ConnTest, only: [build_conn: 0, put_req_cookie: 3, dispatch: 5]
  import Plug.Conn

  alias Dawarich.{RailsCookies, RailsSecret}
  alias Dawarich.Test.RailsUser

  def upstream! do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
    upstream
  end

  def post_form(session, body, headers \\ [], path \\ "/exports") do
    headers
    |> Enum.reduce(build_conn(), fn {name, value}, conn -> put_req_header(conn, name, value) end)
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded;charset=UTF-8")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> dispatch(DawarichWeb.Endpoint, :post, path, body)
  end

  def rails_session(conn) do
    {:ok, session} =
      RailsCookies.decrypt(
        conn.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        RailsSecret.fetch(),
        DateTime.utc_now()
      )

    session
  end

  def forwarded(upstream, fun) do
    puma =
      Task.async(fn ->
        socket = accept(upstream)
        {head, rest} = read_head(socket)
        length = head |> header("content-length") |> List.first("0") |> String.to_integer()
        body = read_at_least(socket, rest, length)
        reply(socket, "HTTP/1.1 204 No Content\r\n\r\n")
        {request_line(head), body}
      end)

    conn = fun.()
    {Task.await(puma), conn}
  end
end
