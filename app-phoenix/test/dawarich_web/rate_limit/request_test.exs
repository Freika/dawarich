defmodule DawarichWeb.RateLimit.RequestTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias Dawarich.{RailsCookies, RailsSecret}
  alias Dawarich.Test.RateLimitCorpus
  alias DawarichWeb.RateLimit.Request

  defp corpus, do: RateLimitCorpus.corpus()

  defp vector_conn(v) do
    conn = Plug.Test.conn(v["method"], "/x?" <> v["query"], v["body"])
    conn = put_req_header(conn, "content-length", Integer.to_string(byte_size(v["body"])))
    if v["content_type"], do: put_req_header(conn, "content-type", v["content_type"]), else: conn
  end

  defp json_conn(body) do
    Plug.Test.conn(:post, "/api/v1/auth/login", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
  end

  defp check({:defer, _reason, _conn}, _rails, true, _v), do: :ok
  defp check({:ok, map, _conn}, rails, false, v), do: assert(map == rails, inspect(v))

  defp check(other, _rails, defer?, v),
    do: flunk("#{inspect(v)} defer=#{defer?}: #{inspect(other, limit: 4)}")

  test "the normalized path and the throttle path equal Rails' for every recorded path" do
    for v <- corpus()["paths"] do
      facts = Request.facts(Plug.Test.conn(:get, "http://www.example.com" <> v["raw"]), false)
      assert {facts.path, facts.throttle_path} == {v["path"], v["throttle_path"]}, v["raw"]
    end
  end

  test "the media type and JSON detection equal Rack's media_type and json_request?" do
    for v <- corpus()["media_types"] do
      conn = put_req_header(Plug.Test.conn(:post, "/"), "content-type", v["content_type"])
      facts = Request.facts(conn, false)
      assert {facts.media_type, facts.json} == {v["media_type"], v["json"]}, inspect(v)
    end
  end

  test "params and body params equal safe_params and safe_body_params; shapes Rack parses differently are deferred" do
    for v <- corpus()["params"] do
      conn = vector_conn(v)
      facts = Request.facts(conn, false)
      check(Request.params(conn, facts), v["safe_params"], "params" in (v["defer"] || []), v)

      check(
        Request.body_params(conn, facts),
        v["safe_body_params"],
        "body" in (v["defer"] || []),
        v
      )
    end
  end

  test "a JSON body is read once, kept for the pipeline and the proxy, and ignored above 16 KiB" do
    body = ~s({"email":"a@example.invalid"})
    conn = json_conn(body)

    assert {:ok, %{"email" => "a@example.invalid"}, conn} =
             Request.body_params(conn, Request.facts(conn, false))

    assert conn.private.dawarich_raw_body == body

    assert {:ok, %{"email" => "a@example.invalid"}, _} =
             Request.body_params(conn, Request.facts(conn, false))

    big = json_conn(String.duplicate(" ", 16_385))
    assert {:ok, %{}, big} = Request.body_params(big, Request.facts(big, false))
    refute Map.has_key?(big.private, :dawarich_raw_body)
  end

  test "the Rails session cookie is read; a second Cookie header is deferred" do
    value = RailsCookies.encrypt(%{"otp_user_id" => 7}, "_dawarich_session", RailsSecret.fetch())

    conn =
      put_req_header(
        Plug.Test.conn(:post, "/users/otp_challenge"),
        "cookie",
        "_dawarich_session=" <> value
      )

    assert {:ok, %{"otp_user_id" => 7}, _} = Request.session(conn)

    assert {:ok, %{}, _} =
             Request.session(put_req_header(Plug.Test.conn(:post, "/"), "cookie", "a=1"))

    two = %{conn | req_headers: conn.req_headers ++ [{"cookie", "a=1"}]}
    assert {:defer, "ambiguous session cookie", _} = Request.session(two)
  end

  test "ruby_to_s is Ruby's to_s for nil, strings, integers and booleans and refuses anything else" do
    assert Enum.map([nil, "a", 42, false, true], &Request.ruby_to_s/1) == [
             nil,
             "a",
             "42",
             "false",
             "true"
           ]

    assert_raise ArgumentError, fn -> Request.ruby_to_s(%{"x" => 1}) end
    assert_raise ArgumentError, fn -> Request.ruby_to_s(1.5) end
  end
end
