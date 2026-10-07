defmodule DawarichWeb.ApiDocs do
  @moduledoc false

  import Plug.Conn

  @index """
  <!DOCTYPE html>
  <html lang="en">
  <head>
  <meta charset="utf-8"><title>Dawarich API</title>
  <link rel="stylesheet" href="/api-docs/swagger-ui.css">
  </head>
  <body>
  <h1>Dawarich API</h1>
  <p><a href="/api-docs/v1/swagger.yaml">OpenAPI description (YAML)</a></p>
  <p><a href="https://dawarich.app/docs/api/dawarich-api">API reference on dawarich.app</a></p>
  <div id="swagger-ui"></div>
  <script src="/api-docs/swagger-ui-bundle.js"></script>
  <script>
  window.onload = function() {
    window.ui = SwaggerUIBundle({
      url: "/api-docs/v1/swagger.yaml",
      dom_id: "#swagger-ui",
      deepLinking: true,
      validatorUrl: null,
      presets: [SwaggerUIBundle.presets.apis],
      layout: "BaseLayout"
    });
  };
  </script>
  </body>
  </html>
  """

  @assets %{
    "swagger-ui-bundle.js" => "text/javascript",
    "swagger-ui.css" => "text/css",
    "LICENSE" => "text/plain"
  }

  def init(opts), do: opts

  def call(
        %Plug.Conn{method: method, path_info: ["api-docs", "v1", "swagger.yaml"]} = conn,
        _opts
      )
      when method in ["GET", "HEAD"] do
    conn
    |> put_resp_content_type("text/yaml", nil)
    |> send_file(200, Dawarich.RailsRoot.join("swagger/v1/swagger.yaml"))
  end

  def call(%Plug.Conn{method: method, path_info: path} = conn, _opts)
      when method in ["GET", "HEAD"] and path in [["api-docs"], ["api-docs", "index.html"]] do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, @index)
  end

  def call(%Plug.Conn{method: method, path_info: ["api-docs", asset]} = conn, _opts)
      when method in ["GET", "HEAD"] and is_map_key(@assets, asset) do
    root = Application.get_env(:dawarich, :public_root) || Dawarich.RailsRoot.join("public")

    conn
    |> put_resp_content_type(Map.fetch!(@assets, asset), nil)
    |> send_file(200, Path.join([root, "api-docs", asset]))
  end

  def call(conn, _opts), do: send_resp(conn, 404, "")
end
