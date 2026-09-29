defmodule DawarichWeb.Api.IngestControllerTest do
  use Dawarich.IngestCase, async: false

  import Plug.Conn
  import Plug.Test
  import Dawarich.Test.RawHTTP
  import ExUnit.CaptureLog

  require Logger

  alias DawarichWeb.Api.IngestController

  @moduletag :capture_log

  setup do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
    %{upstream: upstream}
  end

  defp with_info_log(fun) do
    previous = Logger.level()
    Logger.configure(level: :info)

    try do
      capture_log([level: :info], fun)
    after
      Logger.configure(level: previous)
    end
  end

  defp handed_off(conn, upstream) do
    puma =
      Task.async(fn ->
        socket = accept(upstream)
        {head, _rest} = read_head(socket)
        reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
        request_line(head)
      end)

    conn = put_private(conn, :dawarich_raw_body, "")
    result = IngestController.call(conn, :points)
    {Task.await(puma), result}
  end

  test "a non-Unsupported exception in prepare logs only its struct name, never Exception.message/1",
       %{upstream: upstream} do
    user = user!()

    conn =
      conn(:post, "/api/v1/points")
      |> assign(:api_params, [52.9, 13.4])
      |> assign(:api_user, %{id: user})

    log =
      with_info_log(fn ->
        {request_line, result} = handed_off(conn, upstream)
        assert request_line == "POST /api/v1/points HTTP/1.1"
        assert result.halted
      end)

    assert log =~ "[ingest] /api/v1/points handed to Rails: FunctionClauseError"
    refute log =~ "no function clause matching"
  end

  test "an Unsupported exception in prepare logs its reason as-is", %{upstream: upstream} do
    user = user!()

    body =
      ~s({"locations":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"timestamp":1790000000,"battery_level":true}}]})

    conn =
      conn(:post, "/api/v1/points")
      |> assign(:api_params, Jason.decode!(body))
      |> assign(:api_user, %{id: user})

    log =
      with_info_log(fn ->
        {request_line, result} = handed_off(conn, upstream)
        assert request_line == "POST /api/v1/points HTTP/1.1"
        assert result.halted
      end)

    assert log =~ "[ingest] /api/v1/points handed to Rails: to_f of a non-number"
  end
end
