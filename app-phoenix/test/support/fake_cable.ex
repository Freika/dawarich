defmodule Dawarich.Test.FakeCable do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  def start(test) do
    bandit =
      ExUnit.Callbacks.start_supervised!(
        {Bandit, plug: {__MODULE__, test}, ip: {127, 0, 0, 1}, port: 0, startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    port
  end

  @impl Plug
  def init(test), do: test

  @impl Plug
  def call(conn, test) do
    send(test, {:cable_request, conn.request_path, conn.query_string, conn.req_headers})

    if get_req_header(conn, "x-refuse") == [] do
      conn
      |> put_resp_header("sec-websocket-protocol", "actioncable-v1-json")
      |> WebSockAdapter.upgrade(__MODULE__.Socket, test, timeout: :infinity)
      |> halt()
    else
      conn |> put_resp_content_type("text/plain") |> send_resp(404, "Page not found")
    end
  end

  defmodule Socket do
    @moduledoc false
    @behaviour WebSock

    @impl WebSock
    def init(test), do: {:push, [{:text, ~s({"type":"welcome"})}], test}

    @impl WebSock
    def handle_in({"bye", opcode: :text}, test), do: {:stop, :normal, {4000, "bye"}, test}
    def handle_in({text, opcode: :text}, test), do: {:push, [{:text, String.upcase(text)}], test}

    @impl WebSock
    def handle_info(_message, test), do: {:ok, test}

    @impl WebSock
    def terminate(reason, test) do
      send(test, {:cable_closed, reason})
      :ok
    end
  end
end
