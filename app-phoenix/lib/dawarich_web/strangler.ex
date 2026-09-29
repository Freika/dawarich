defmodule DawarichWeb.Strangler do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn, only: [halt: 1]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if owned?(conn),
      do: Plug.Head.call(conn, []),
      else:
        conn
        |> DawarichWeb.RailsProxy.call(Application.fetch_env!(:dawarich, :rails_upstream))
        |> halt()
  end

  defp owned?(conn) do
    method = if conn.method == "HEAD", do: "GET", else: conn.method

    case Phoenix.Router.route_info(DawarichWeb.Router, method, conn.path_info, conn.host) do
      :error -> false
      %{slice: slice} -> DawarichWeb.Slices.owned?(slice)
      _route -> true
    end
  end
end
