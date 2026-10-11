defmodule DawarichWeb.NativeM6Auth do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    conn = DawarichWeb.RailsAuth.call(conn, opts)
    user = conn.assigns[:current_user]

    if user && not (is_nil(user.settings) or is_map(user.settings)),
      do: conn |> send_resp(422, "") |> halt(),
      else: conn
  rescue
    ArgumentError -> conn |> send_resp(422, "") |> halt()
  end
end
