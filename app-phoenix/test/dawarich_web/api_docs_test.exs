defmodule DawarichWeb.ApiDocsTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias DawarichWeb.ApiDocs

  test "serves the stored OpenAPI YAML as text/yaml, HEAD with the same headers and no body" do
    conn = ApiDocs.call(conn(:get, "/api-docs/v1/swagger.yaml"), [])
    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/yaml"]
    assert conn.resp_body == File.read!(Dawarich.RailsRoot.join("swagger/v1/swagger.yaml"))

    head = ApiDocs.call(conn(:head, "/api-docs/v1/swagger.yaml"), [])
    assert {head.status, head.resp_body} == {200, ""}
    assert Plug.Conn.get_resp_header(head, "content-type") == ["text/yaml"]
  end

  test "the index links the YAML and the hosted reference; other paths and methods are 404" do
    for path <- ["/api-docs", "/api-docs/index.html"] do
      conn = ApiDocs.call(conn(:get, path), [])
      assert conn.status == 200
      assert conn.resp_body =~ ~s(href="/api-docs/v1/swagger.yaml")
      assert conn.resp_body =~ ~s(href="https://dawarich.app/docs/api/dawarich-api")
    end

    assert ApiDocs.call(conn(:get, "/api-docs/v2/swagger.yaml"), []).status == 404
    assert ApiDocs.call(conn(:post, "/api-docs"), []).status == 404
  end
end
