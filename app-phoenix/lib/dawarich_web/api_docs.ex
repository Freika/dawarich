defmodule DawarichWeb.ApiDocs do
  @moduledoc false

  import Plug.Conn

  @index """
  <!DOCTYPE html>
  <html lang="en">
  <head><meta charset="utf-8"><title>Dawarich API</title></head>
  <body>
  <h1>Dawarich API</h1>
  <p><a href="/api-docs/v1/swagger.yaml">OpenAPI description (YAML)</a></p>
  <p><a href="https://dawarich.app/docs/api/dawarich-api">API reference on dawarich.app</a></p>
  </body>
  </html>
  """

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

  def call(conn, _opts), do: send_resp(conn, 404, "")
end
