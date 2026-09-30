defmodule DawarichWeb.Api.BodyTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test
  import Dawarich.Test.RawHTTP
  import ExUnit.CaptureLog

  require Logger

  alias DawarichWeb.Api.Body

  defp with_info_log(fun) do
    previous = Logger.level()
    Logger.configure(level: :info)

    try do
      capture_log([level: :info], fun)
    after
      Logger.configure(level: previous)
    end
  end

  setup do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
    %{upstream: upstream}
  end

  defp request(target, type, body) do
    conn(:post, target, body)
    |> put_req_header("content-type", type)
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> assign(:api_tag, "ingest")
  end

  defp forwarded(upstream, conn) do
    puma =
      Task.async(fn ->
        socket = accept(upstream)
        {head, rest} = read_head(socket)
        length = head |> header("content-length") |> List.first("0") |> String.to_integer()
        body = read_at_least(socket, rest, length)
        reply(socket, "HTTP/1.1 204 No Content\r\n\r\n")
        {request_line(head), body}
      end)

    result = Body.call(conn, [])
    {Task.await(puma), result}
  end

  test "JSON: query wins, non-objects become _json, nils leave arrays" do
    conn =
      Body.call(
        request(
          "/api/v1/points?api_key=q",
          "application/json; charset=utf-8",
          ~s({"api_key":"b","a":[1,null,{"b":[null]}]})
        ),
        []
      )

    assert conn.assigns.api_params == %{"api_key" => "q", "a" => [1, %{"b" => []}]}

    assert Body.call(request("/x", "text/x-json", "[1]"), []).assigns.api_params == %{
             "_json" => [1]
           }

    assert Body.call(request("/x", "application/json", ""), []).assigns.api_params == %{}
  end

  test "flat form pairs are decoded; the shapes Rack parses differently go to Rails", %{
    upstream: upstream
  } do
    assert Body.call(request("/x", "application/x-www-form-urlencoded", "id=a+b"), []).assigns.api_params ==
             %{"id" => "a b"}

    assert Body.call(
             request("/x", "application/x-www-form-urlencoded", "id=a&lat=52.5&id=c"),
             []
           ).assigns.api_params == %{"id" => "c", "lat" => "52.5"}

    body = "locations[][geometry]=1"

    assert {{"POST /x HTTP/1.1", ^body}, %{halted: true}} =
             forwarded(upstream, request("/x", "application/x-www-form-urlencoded", body))
  end

  test "a body Jason rejects reaches Puma byte for byte", %{upstream: upstream} do
    body = ~s({"locations":[] /* c */})

    assert {{"POST /api/v1/points HTTP/1.1", ^body}, _} =
             forwarded(upstream, request("/api/v1/points", "application/json", body))
  end

  test "a multipart body reaches Puma byte for byte through the proxy branch", %{
    upstream: upstream
  } do
    body = "--X\r\nContent-Disposition: form-data; name=upload\r\n\r\nhello\r\n--X--\r\n"

    assert {{"POST /api/v1/points HTTP/1.1", ^body}, %{halted: true}} =
             forwarded(
               upstream,
               request("/api/v1/points", "multipart/form-data; boundary=X", body)
             )
  end

  test "a JSON-shaped multipart body reaches Puma without JSON decoding", %{upstream: upstream} do
    body = ~s({"upload":"hello"})

    assert {{"POST /api/v1/points HTTP/1.1", ^body}, %{halted: true}} =
             forwarded(
               upstream,
               request("/api/v1/points", "multipart/form-data; boundary=X", body)
             )
  end

  test "a Jason-rejected body larger than one MiB reaches Puma byte for byte", %{
    upstream: upstream
  } do
    body = "{\"locations\":[]" <> :binary.copy(" ", 1_048_576) <> "/* c */}"

    assert {{"POST /api/v1/points HTTP/1.1", ^body}, %{halted: true}} =
             forwarded(upstream, request("/api/v1/points", "application/json", body))
  end

  test "a body larger than two MiB reaches Puma unread", %{upstream: upstream} do
    body = :binary.copy("x", 2_097_153)
    conn = request("/api/v1/points", "application/json", body)

    assert Body.kind(conn) == :proxy

    assert {{"POST /api/v1/points HTTP/1.1", ^body}, %{halted: true}} =
             forwarded(upstream, conn)
  end

  test "an unread proxy branch (oversized or other content type) logs a hand-off reason", %{
    upstream: upstream
  } do
    oversized = :binary.copy("x", 2_097_153)

    cases = [
      {request("/api/v1/points", "application/json", oversized), "body larger than 2 MiB"},
      {request("/api/v1/points", "multipart/form-data; boundary=X", "--X--"),
       "content type multipart/form-data"}
    ]

    for {conn, expected} <- cases do
      log = with_info_log(fn -> {_puma, _result} = forwarded(upstream, conn) end)
      assert log =~ "[ingest] /api/v1/points handed to Rails: #{expected}", expected
    end
  end

  test "form pairs after an ampersand space decode as Rack does" do
    assert Body.call(request("/x", "application/x-www-form-urlencoded", "a=1& b=2"), []).assigns.api_params ==
             %{"a" => "1", "b" => "2"}
  end

  test "a form body with more ampersands than Rack allows reaches Puma", %{upstream: upstream} do
    body = String.duplicate("&", 4_097)

    assert {{"POST /api/v1/points HTTP/1.1", ^body}, %{halted: true}} =
             forwarded(
               upstream,
               request("/api/v1/points", "application/x-www-form-urlencoded", body)
             )
  end

  test "multipart, chunked, oversized and untyped bodies go to Puma unread" do
    assert Body.kind(request("/x", "multipart/form-data; boundary=X", "--X--")) == :proxy

    assert Body.kind(conn(:post, "/x", "a") |> put_req_header("transfer-encoding", "chunked")) ==
             :proxy

    assert Body.kind(
             request("/x", "application/json", "{}")
             |> put_req_header("content-length", "16777217")
           ) ==
             :proxy

    assert Body.kind(conn(:post, "/x", "a") |> put_req_header("content-length", "1")) == :proxy
    assert Body.kind(conn(:post, "/x", "")) == :none
  end
end
