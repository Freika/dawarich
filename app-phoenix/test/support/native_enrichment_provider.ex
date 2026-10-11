defmodule Dawarich.Test.NativeEnrichmentProvider do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def start(owner, scan_status \\ 200) do
    pid =
      ExUnit.Callbacks.start_supervised!(
        {Bandit, plug: {__MODULE__, {owner, scan_status}}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}"
  end

  def init(options), do: options

  def call(conn, {owner, scan_status}) do
    {:ok, body, conn} = read_body(conn)
    send(owner, {:enrichment_request, conn.method, conn.request_path, body})

    {status, response} =
      if conn.request_path == "/api/search/metadata" do
        items =
          if Jason.decode!(body)["page"] == 1 do
            for id <- ~w(selected other),
                do: %{
                  "id" => id,
                  "type" => "IMAGE",
                  "originalFileName" => id <> ".jpg",
                  "fileCreatedAt" => "2026-03-30T09:00:00Z",
                  "exifInfo" => %{}
                }
          else
            []
          end

        {scan_status, %{"assets" => %{"items" => items}}}
      else
        {200, %{}}
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(response))
  end
end
