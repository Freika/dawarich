defmodule DawarichWeb.A8Gate do
  @moduledoc false

  def actions?(conn, _params) do
    action_query?(conn) and
      Plug.Conn.get_req_header(conn, "x-dawarich-client") == [] and
      Plug.Conn.get_req_header(conn, "x-http-method-override") == [] and
      action_content?(conn) and
      not String.contains?(List.last(conn.path_info) || "", ".")
  end

  defp action_query?(conn), do: request_gate(conn).actions?(conn, %{})

  def request_gate(%{path_info: ["trips" | _]}), do: DawarichWeb.TripRequestGate
  def request_gate(%{path_info: ["places" | _]}), do: DawarichWeb.PlaceRequestGate
  def request_gate(%{path_info: ["route_videos" | _]}), do: DawarichWeb.RouteVideoRequestGate
  def request_gate(_), do: DawarichWeb.VisitRequestGate

  defp action_content?(conn) do
    DawarichWeb.Api.Body.kind(conn) in [:form, :none] or
      case Plug.Conn.get_req_header(conn, "content-type") do
        [type] ->
          match?(
            {:ok, "multipart", "form-data", %{"boundary" => _}},
            Plug.Conn.Utils.media_type(type)
          ) and
            not DawarichWeb.RailsProxy.Headers.chunked?(conn) and
            bounded_length?(Plug.Conn.get_req_header(conn, "content-length"))

        _ ->
          false
      end
  end

  defp bounded_length?([length]) do
    case Integer.parse(length) do
      {size, ""} -> size in 0..2_097_152
      _ -> false
    end
  end

  defp bounded_length?(_), do: false

  def navigation?(conn, params), do: DawarichWeb.VisitRequestGate.navigation?(conn, params)
  def settings?(conn, params), do: DawarichWeb.VisitRequestGate.settings?(conn, params)

  def scalar_query?(raw, allowed) do
    false = Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, raw)
    pairs = URI.query_decoder(raw) |> Enum.to_list()

    Enum.all?(pairs, fn {key, value} -> key in allowed and String.valid?(value) end) and
      length(pairs) == length(Enum.uniq_by(pairs, &elem(&1, 0)))
  rescue
    _ -> false
  end
end
