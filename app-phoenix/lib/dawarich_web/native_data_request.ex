defmodule DawarichWeb.NativeDataRequest do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def prepare(conn), do: conn

  def call(conn, _) do
    conn = conn |> fetch_query_params() |> DawarichWeb.NativeM6Auth.call([])
    conn = put_private(conn, :native_data_document, true)

    if conn.halted, do: conn, else: envelope(conn)
  end

  defp envelope(conn) do
    if conn.query_params["format"] not in [nil, "html"] do
      conn |> send_resp(422, "") |> halt()
    else
      conn
    end
  end
end
