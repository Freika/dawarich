defmodule DawarichWeb.MapDataGate do
  @moduledoc false

  alias Dawarich.{PointList, TagPages}
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

  def tags?(conn, _params),
    do: conn.query_string == "" and Plug.Conn.get_req_header(conn, "x-dawarich-client") == []

  def tag_edit?(conn, %{"id" => id}) do
    tags?(conn, %{}) and Regex.match?(~r/\A\d{1,18}\z/, id) and
      TripsGate.open?(conn, &(TagPages.edit(&1, String.to_integer(id)) != :rails))
  end
end
