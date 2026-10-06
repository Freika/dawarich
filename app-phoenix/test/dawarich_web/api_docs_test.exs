defmodule DawarichWeb.ApiDocsTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias DawarichWeb.ApiDocs

  setup do
    previous = Application.get_env(:dawarich, :rails_upstream)
    hosted = System.get_env("SELF_HOSTED")
    Application.put_env(:dawarich, :rails_upstream, nil)

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, previous)
      if hosted, do: System.put_env("SELF_HOSTED", hosted), else: System.delete_env("SELF_HOSTED")
    end)

    :ok
  end

  test "Endpoint serves the exact rswag document on self hosted and Cloud without Rails" do
    yaml = File.read!(Dawarich.RailsRoot.join("swagger/v1/swagger.yaml"))

    for hosted <- ["true", "false"] do
      System.put_env("SELF_HOSTED", hosted)

      for method <- [:get, :head] do
        response = endpoint(method, "/api-docs/v1/swagger.yaml")
        assert response.status == 200
        assert Plug.Conn.get_resp_header(response, "content-type") == ["text/yaml"]
        assert response.resp_body == if(method == :head, do: "", else: yaml)

        for path <- ["/api-docs", "/api-docs/index.html"] do
          response = endpoint(method, path)
          assert response.status == 200
          if method == :head, do: assert(response.resp_body == "")
        end
      end

      for {method, path} <- [
            {:get, "/api-docs/v2/swagger.yaml"},
            {:post, "/api-docs"},
            {:delete, "/api-docs/v1/swagger.yaml"}
          ] do
        assert endpoint(method, path).status == 404
      end
    end
  end

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

  defp endpoint(method, path),
    do: DawarichWeb.Endpoint.call(conn(method, path), DawarichWeb.Endpoint.init([]))
end
