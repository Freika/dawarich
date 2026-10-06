defmodule DawarichWeb.Api.HeadGoldenReviewTest do
  use Dawarich.ApiEndpointCase

  import Dawarich.Test.RawHTTP

  @moduletag :capture_log
  @tag :review_head_golden
  test "HEAD golden rejects wire entities and absent or arbitrary representation lengths", c do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    fixture = Jason.decode!(File.read!("test/fixtures/api_foundation/golden.json"))

    kase =
      fixture["cases"]
      |> Enum.find(&(&1["name"] == "rails_head_plan"))
      |> Map.put("expect", "own")

    get = Enum.find(fixture["cases"], &(&1["name"] == "plan_mobile_bearer_json"))
    length = byte_size(get["response"]["body"])
    assert length == 300
    assert kase["response"]["headers"]["etag"] == get["response"]["headers"]["etag"]

    assert :ok == check_reply(kase, ["Content-Length: #{length}\r\n"], "")

    for {framing, bytes} <- [
          {["Content-Length: #{length}\r\n"], "unexpected-entity"},
          {[], ""},
          {["Content-Length: 777\r\n"], ""}
        ] do
      assert_raise ExUnit.AssertionError, fn -> check_reply(kase, framing, bytes) end
    end

    for row <- kase["setup"], do: Dawarich.Test.ApiGolden.insert!("users", row)
    Dawarich.Test.ApiGolden.check(kase, c.port, c.upstream)
  end

  defp check_reply(kase, framing, bytes) do
    endpoint = listen()
    upstream = listen()

    server =
      Task.async(fn ->
        socket = accept(endpoint)
        read_head(socket)

        headers =
          Enum.map(kase["response"]["headers"], fn {name, value} -> "#{name}: #{value}\r\n" end)

        reply(socket, ["HTTP/1.1 200 OK\r\n", headers, framing, "\r\n"])
        reply(socket, bytes)
        :gen_tcp.close(socket)
      end)

    try do
      Dawarich.Test.ApiGolden.check(kase, endpoint.port, upstream)
      :ok
    after
      Task.await(server)
      :gen_tcp.close(endpoint.listen)
      :gen_tcp.close(upstream.listen)
    end
  end
end
