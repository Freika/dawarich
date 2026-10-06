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

  test "Swagger UI initializes against the stored YAML with locally served assets" do
    root = Path.join(System.tmp_dir!(), "swagger-ui-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "api-docs"))

    for file <- ["swagger-ui-bundle.js", "swagger-ui.css", "LICENSE"] do
      File.cp!(
        Dawarich.RailsRoot.join("node_modules/swagger-ui-dist/" <> file),
        Path.join([root, "api-docs", file])
      )
    end

    File.write!(Path.join([root, "api-docs", "package.json"]), "private build metadata")
    saved = Map.new([:public_root, :public_files], &{&1, Application.fetch_env(:dawarich, &1)})
    Application.put_env(:dawarich, :public_root, root)

    Application.put_env(:dawarich, :public_files, %{
      env: %{"RAILS_ENV" => "production", "APPLICATION_PROTOCOL" => "http"},
      rails_env: "production",
      root: root
    })

    on_exit(fn ->
      File.rm_rf!(root)

      Enum.each(saved, fn
        {key, {:ok, value}} -> Application.put_env(:dawarich, key, value)
        {key, :error} -> Application.delete_env(:dawarich, key)
      end)
    end)

    html = endpoint(:get, "/api-docs").resp_body
    assert html =~ "SwaggerUIBundle({"
    assert html =~ ~s(url: "/api-docs/v1/swagger.yaml")
    assert html =~ ~s(dom_id: "#swagger-ui")
    assert html =~ ~s(validatorUrl: null)
    assert html =~ ~s(src="/api-docs/swagger-ui-bundle.js")
    assert html =~ ~s(href="/api-docs/swagger-ui.css")
    refute html =~ "petstore"
    refute html =~ "unpkg"

    for {file, type} <- [
          {"swagger-ui-bundle.js", "text/javascript"},
          {"swagger-ui.css", "text/css"},
          {"LICENSE", "text/plain"}
        ] do
      response = endpoint(:get, "/api-docs/" <> file)
      assert response.status == 200
      assert Plug.Conn.get_resp_header(response, "content-type") == [type]

      assert response.resp_body ==
               File.read!(Dawarich.RailsRoot.join("node_modules/swagger-ui-dist/" <> file))

      head = endpoint(:head, "/api-docs/" <> file)
      assert {head.status, head.resp_body} == {200, ""}
      assert Plug.Conn.get_resp_header(head, "content-type") == [type]
    end

    for path <- ["package.json", "swagger-ui-bundle.js.map", "index.css", "../Gemfile"] do
      assert endpoint(:get, "/api-docs/" <> path).status == 404
    end
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
