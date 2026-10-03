defmodule DawarichWeb.MapDataGate do
  @moduledoc false

  alias Dawarich.PointList
  alias DawarichWeb.{LayoutAssigns, TripsGate}

  def points?(conn, _params) do
    params = Plug.Conn.Query.decode(conn.query_string)

    PointList.valid_params?(params) and Plug.Conn.get_req_header(conn, "x-dawarich-client") == [] and
      TripsGate.open?(conn, fn user ->
        PointList.load(user, params, DateTime.utc_now(),
          self_hosted: LayoutAssigns.self_hosted?()
        ) != :rails
      end)
  end
end
