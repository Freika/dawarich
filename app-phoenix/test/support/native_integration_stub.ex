defmodule Dawarich.Test.NativeIntegrationStub do
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, opts) do
    send(opts[:owner], {:native_provider_request, conn.request_path})

    body =
      case conn.request_path do
        "/api/v1/trips" ->
          %{
            trips: [
              %{
                id: "dated",
                title: "Dated trip",
                start_date: "2030-01-01",
                end_date: "2030-01-02"
              },
              %{id: "undated", title: "Undated trip"},
              %{id: "archived", archived: true, start_date: "2030-01-01", end_date: "2030-01-02"}
            ]
          }

        "/api/flight/list" ->
          %{success: true, flights: []}

        "/api/v1/cars" ->
          %{data: %{cars: []}}

        _ ->
          %{assets: %{items: []}}
      end

    status = if String.starts_with?(conn.request_path, "/fail"), do: 401, else: 200
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end

  def start! do
    server =
      ExUnit.Callbacks.start_supervised!(
        {Bandit,
         plug: {__MODULE__, owner: self()}, port: 0, ip: {127, 0, 0, 1}, startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    "http://127.0.0.1:#{port}"
  end
end
