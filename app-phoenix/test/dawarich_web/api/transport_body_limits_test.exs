defmodule DawarichWeb.Api.TransportBodyLimitsTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias DawarichWeb.Api.Transport

  setup do
    previous = Application.get_env(:dawarich, :api_body_limits)
    Application.put_env(:dawarich, :api_body_limits, json: 4_096, multipart: 16_384)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :api_body_limits, previous),
        else: Application.delete_env(:dawarich, :api_body_limits)
    end)
  end

  defp native(method, body, type) do
    conn(method, "/api/v1/points", body)
    |> put_req_header("content-type", type)
    |> put_req_header("accept", "application/json")
    |> assign(:api_tag, "api")
    |> put_private(:dawarich_native_api, true)
  end

  defp multipart(parts) do
    boundary = "transport-limit-boundary"

    body =
      Enum.map_join(parts, fn {name, filename, content} ->
        disposition =
          if filename,
            do: ~s(form-data; name="#{name}"; filename="#{filename}"),
            else: ~s(form-data; name="#{name}")

        "--#{boundary}\r\ncontent-disposition: #{disposition}\r\n\r\n#{content}\r\n"
      end) <> "--#{boundary}--\r\n"

    {body, "multipart/form-data; boundary=#{boundary}"}
  end

  test "a JSON body within the limit is parsed" do
    body = Jason.encode!(%{"payload" => String.duplicate("x", 1_000)})
    conn = Transport.parse(native(:post, body, "application/json"))

    refute conn.halted
    assert conn.assigns.api_params["payload"] == String.duplicate("x", 1_000)
  end

  test "a JSON body over the limit is rejected with 413 before it is decoded" do
    body = Jason.encode!(%{"payload" => String.duplicate("x", 5_000)})
    conn = Transport.parse(native(:post, body, "application/json"))

    assert conn.halted
    assert conn.status == 413
    assert Jason.decode!(conn.resp_body) == %{"status" => 413, "error" => "Content Too Large"}
    refute conn.assigns[:api_params]["payload"]
  end

  test "the JSON limit counts bytes actually read, not the content-length header" do
    body = Jason.encode!(%{"payload" => String.duplicate("x", 5_000)})

    conn =
      native(:post, body, "application/json")
      |> put_req_header("content-length", "10")
      |> Transport.parse()

    assert conn.status == 413
  end

  test "a form body over the limit is rejected with 413" do
    body = "payload=" <> String.duplicate("x", 5_000)
    conn = Transport.parse(native(:post, body, "application/x-www-form-urlencoded"))

    assert conn.status == 413
  end

  test "a 413 for a client that does not ask for JSON still responds" do
    body = Jason.encode!(%{"payload" => String.duplicate("x", 5_000)})

    conn =
      conn(:post, "/api/v1/points", body)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "text/html")
      |> assign(:api_tag, "api")
      |> put_private(:dawarich_native_api, true)
      |> Transport.parse()

    assert conn.status == 413
    assert conn.resp_body =~ "Content Too Large"
  end

  test "a multipart body over the limit is rejected with 413, not 400" do
    {body, type} = multipart([{"file", "big.gpx", String.duplicate("x", 20_000)}])
    conn = Transport.parse(native(:post, body, type))

    assert conn.halted
    assert conn.status == 413
  end

  test "a multipart upload within the limit keeps its file and fields" do
    {body, type} =
      multipart([{"name", nil, "trip"}, {"file", "small.gpx", String.duplicate("y", 10_000)}])

    conn = Transport.parse(native(:post, body, type))

    refute conn.halted
    assert conn.assigns.api_params["name"] == "trip"
    assert %Plug.Upload{path: path} = conn.assigns.api_params["file"]
    assert File.read!(path) == String.duplicate("y", 10_000)
  end

  test "a small multipart body stays available as the raw body" do
    {body, type} = multipart([{"name", nil, "trip"}])
    conn = Transport.parse(native(:post, body, type))

    assert conn.private.dawarich_raw_body == body
  end

  test "a large multipart upload is not also kept in memory as the raw body" do
    Application.put_env(:dawarich, :api_body_limits, json: 4_096, multipart: 8_388_608)
    content = String.duplicate("z", 3 * 1_048_576)
    {body, type} = multipart([{"file", "large.gpx", content}])
    conn = Transport.parse(native(:post, body, type))

    refute conn.halted
    assert %Plug.Upload{path: path} = conn.assigns.api_params["file"]
    assert File.stat!(path).size == byte_size(content)
    refute Map.has_key?(conn.private, :dawarich_raw_body)
  end
end
