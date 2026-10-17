defmodule DawarichWeb.Api.BodyTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test
  import Dawarich.Test.RawHTTP

  alias DawarichWeb.Api.Body

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

  defp refused(upstream, conn) do
    result = Body.call(conn, [])
    assert result.status == 422
    assert result.halted
    assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 0)
    result
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

  test "flat form pairs are decoded; the shapes Rack parses differently refuse locally", %{
    upstream: upstream
  } do
    assert Body.call(request("/x", "application/x-www-form-urlencoded", "id=a+b"), []).assigns.api_params ==
             %{"id" => "a b"}

    assert Body.call(
             request("/x", "application/x-www-form-urlencoded", "id=a&lat=52.5&id=c"),
             []
           ).assigns.api_params == %{"id" => "c", "lat" => "52.5"}

    body = "locations[][geometry]=1"

    refused(upstream, request("/x", "application/x-www-form-urlencoded", body))
  end

  test "a body Jason rejects refuses locally", %{upstream: upstream} do
    body = ~s({"locations":[] /* c */})

    refused(upstream, request("/api/v1/points", "application/json", body))
  end

  test "a multipart body refuses locally without decoding", %{
    upstream: upstream
  } do
    body = "--X\r\nContent-Disposition: form-data; name=upload\r\n\r\nhello\r\n--X--\r\n"

    refused(
      upstream,
      request("/api/v1/points", "multipart/form-data; boundary=X", body)
    )
  end

  test "a JSON-shaped multipart body refuses locally without JSON decoding", %{upstream: upstream} do
    body = ~s({"upload":"hello"})

    refused(
      upstream,
      request("/api/v1/points", "multipart/form-data; boundary=X", body)
    )
  end

  test "a Jason-rejected body larger than one MiB refuses locally", %{
    upstream: upstream
  } do
    body = "{\"locations\":[]" <> :binary.copy(" ", 1_048_576) <> "/* c */}"

    refused(upstream, request("/api/v1/points", "application/json", body))
  end

  test "a body larger than two MiB refuses locally unread", %{upstream: upstream} do
    body = :binary.copy("x", 2_097_153)
    conn = request("/api/v1/points", "application/json", body)

    assert Body.kind(conn) == :proxy

    refused(upstream, conn)
  end

  test "unread oversized and unsupported bodies refuse locally without upstream traffic", %{
    upstream: upstream
  } do
    for conn <- [
          request("/api/v1/points", "application/json", :binary.copy("x", 2_097_153)),
          request("/api/v1/points", "multipart/form-data; boundary=X", "--X--")
        ],
        do: refused(upstream, conn)
  end

  test "form pairs after an ampersand space decode as Rack does" do
    assert Body.call(request("/x", "application/x-www-form-urlencoded", "a=1& b=2"), []).assigns.api_params ==
             %{"a" => "1", "b" => "2"}
  end

  test "a form body with more ampersands than Rack allows refuses locally", %{upstream: upstream} do
    body = String.duplicate("&", 4_097)

    refused(
      upstream,
      request("/api/v1/points", "application/x-www-form-urlencoded", body)
    )
  end

  test "multipart, chunked, oversized and untyped bodies remain classified as unread refusals" do
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

  test "a body the rate limiter already read is decoded without reading the socket again" do
    body = "api_key=k&a=1"

    conn =
      conn(:post, "/api/v1/points", "")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(body)))
      |> put_private(:dawarich_raw_body, body)
      |> assign(:api_tag, "ingest")
      |> Body.call([])

    assert conn.assigns.api_params == %{"api_key" => "k", "a" => "1"}
  end
end
