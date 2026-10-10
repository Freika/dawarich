defmodule DawarichWeb.RequestLogger do
  @behaviour Plug
  def init(opts), do: Plug.Logger.init(opts)

  def call(conn, opts) do
    path = conn.request_path

    conn
    |> Map.put(:request_path, Dawarich.LogRedaction.request_path(path))
    |> Plug.Logger.call(opts)
    |> Map.put(:request_path, path)
  end
end
