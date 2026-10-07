defmodule DawarichWeb.RailsRedirectTest do
  use ExUnit.Case, async: true
  alias DawarichWeb.RailsRedirect

  @tag :safe_back3
  test "F2 safe Referer uses request host while rejecting browser authority ambiguities" do
    conn = Plug.Test.conn(:get, "http://www.example.com/map/v2")

    for value <- [
          "http://evil.example\\@www.example.com/offer",
          "//evil.example\\@www.example.com/offer",
          "http://user@www.example.com/map/v2",
          "//www.example.com:8443/map/v2",
          "//evil.example/offer",
          "/\\evil.example/offer",
          "http://www.example.com.evil.example/offer",
          "http://%77ww.example.com/offer",
          "https://[invalid/offer",
          "javascript:alert(1)",
          "map/v2",
          "/map/v2 bad",
          "/map/v2\tbad",
          "/map/v2\r\nbad",
          "/map/v2" <> <<127>>
        ] do
      input = %{conn | req_headers: [{"referer", value}]}
      assert RailsRedirect.back(input) == "http://www.example.com/", inspect(value)
    end

    for {value, expected} <- [
          {"https://www.example.com:8443/map/v2?date=2026-10-07#timeline",
           "https://www.example.com:8443/map/v2?date=2026-10-07#timeline"},
          {"http://www.example.com:8443/map/v2", "http://www.example.com:8443/map/v2"},
          {"/map/v2?date=2026-10-07#timeline",
           "http://www.example.com/map/v2?date=2026-10-07#timeline"}
        ] do
      assert RailsRedirect.back(Plug.Conn.put_req_header(conn, "referer", value)) == expected
    end

    forwarded =
      conn
      |> Plug.Conn.put_req_header("x-forwarded-host", "proxy.example.invalid")
      |> Plug.Conn.put_req_header("referer", "http://proxy.example.invalid/offer")

    assert RailsRedirect.back(forwarded) == "http://proxy.example.invalid/"
    assert RailsRedirect.back(conn) == "http://www.example.com/"

    assert RailsRedirect.back(%{
             conn
             | req_headers: [{"referer", "/map"}, {"referer", "/points"}]
           }) == "http://www.example.com/"
  end

  @tag :safe_back3
  test "native Referer redirects cannot bypass the shared safe helper" do
    offenders =
      for path <- Path.wildcard("lib/dawarich_web/**/*.ex"),
          path != "lib/dawarich_web/rails_redirect.ex",
          ast = Code.string_to_quoted!(File.read!(path)),
          {_ast, reads?} =
            Macro.prewalk(ast, false, fn
              value, seen when is_binary(value) ->
                {value, seen or String.downcase(value) in ["referer", "referrer"]}

              node, seen ->
                {node, seen}
            end),
          reads?,
          do: path

    assert offenders == []
  end
end
