defmodule Dawarich.Test.ImmichEnrichmentStub do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def start(owner, confirmed \\ :all) do
    pid =
      ExUnit.Callbacks.start_supervised!(
        {Bandit, plug: {__MODULE__, {owner, confirmed}}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}"
  end

  def init(opts), do: opts

  def call(conn, {owner, confirmed}) do
    {:ok, body, conn} = read_body(conn)

    send(
      owner,
      {:immich_request, conn.method, conn.request_path, get_req_header(conn, "x-api-key"), body}
    )

    id = List.last(conn.path_info)

    exif =
      if confirmed == :all or id in confirmed,
        do: %{"latitude" => 52.52, "longitude" => 13.405},
        else: %{}

    status = if conn.method == "PUT" and id == "reject", do: 403, else: 200

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{"exifInfo" => exif}))
  end
end
