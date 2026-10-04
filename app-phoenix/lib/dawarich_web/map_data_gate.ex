defmodule DawarichWeb.MapDataGate do
  @moduledoc false

  alias Dawarich.{PointList, TagPages, TrackSegmentPage}
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

  def segments?(conn, %{"track_id" => id}) do
    tags?(conn, %{}) and Regex.match?(~r/\A\d{1,18}\z/, id) and
      TripsGate.open?(conn, &(TrackSegmentPage.load(&1, String.to_integer(id)) != :rails))
  end

  def point_address?(conn, %{"id" => id}) do
    tags?(conn, %{}) and Regex.match?(~r/\A\d{1,18}\z/, id) and
      Plug.Conn.get_req_header(conn, "turbo-frame") == ["point-address-#{id}"] and
      TripsGate.open?(conn, fn user ->
        session = DawarichWeb.RailsAuth.call(conn, []).assigns.rails_session

        valid_token?(session["_csrf_token"]) and
          PointList.address(user, String.to_integer(id)) != :rails
      end)
  end

  defp valid_token?(token) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} -> byte_size(raw) == 32 and Base.url_encode64(raw, padding: false) == token
      _ -> false
    end
  end

  defp valid_token?(_), do: false
end
