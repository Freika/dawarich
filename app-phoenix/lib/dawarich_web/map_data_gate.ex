defmodule DawarichWeb.MapDataGate do
  @moduledoc false

  alias Dawarich.{PointList, TrackSegmentPage}
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

  def segments?(conn, %{"track_id" => id}) do
    plain_request?(conn) and Regex.match?(~r/\A\d{1,18}\z/, id) and
      TripsGate.open?(conn, &(TrackSegmentPage.load(&1, String.to_integer(id)) != :rails))
  end

  def point_address?(conn, %{"id" => id}) do
    plain_request?(conn) and is_binary(id)
  end

  defp plain_request?(conn) do
    query = Plug.Conn.Query.decode(conn.query_string)

    (conn.query_string == "" or
       (Dawarich.Standalone.enabled?() and
          Enum.all?(query, fn {key, value} -> key in ~w(page commit) and is_binary(value) end))) and
      Plug.Conn.get_req_header(conn, "x-dawarich-client") == []
  end
end
