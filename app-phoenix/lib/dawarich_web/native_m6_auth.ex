defmodule DawarichWeb.NativeM6Auth do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    DawarichWeb.RailsAuth.call(conn, opts)
  rescue
    ArgumentError -> conn |> send_resp(422, "") |> halt()
  end
end
