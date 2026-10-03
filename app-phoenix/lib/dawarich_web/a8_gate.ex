defmodule DawarichWeb.A8Gate do
  @moduledoc false
  alias Dawarich.Visits.WebSettings
  alias DawarichWeb.{RailsAuth, Strangler}

  def actions?(conn, _params) do
    conn.query_string == "" and
      Plug.Conn.get_req_header(conn, "x-dawarich-client") == [] and
      Plug.Conn.get_req_header(conn, "x-http-method-override") == [] and
      action_content?(conn) and
      not String.contains?(List.last(conn.path_info) || "", ".")
  end

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

  def navigation?(conn, _params) do
    Strangler.page_request?(conn) and scalar_query?(conn.query_string, ~w(status locale))
  end

  def settings?(conn, _params) do
    scalar_query?(conn.query_string, ~w(locale)) and
      case RailsAuth.call(conn, []).assigns.current_user do
        nil ->
          true

        user ->
          WebSettings.page(
            user,
            WebSettings.load(Dawarich.Repo, user.id),
            DateTime.utc_now(),
            DawarichWeb.LayoutAssigns.self_hosted?()
          ) != :rails
      end
  end

  defp scalar_query?(raw, allowed) do
    false = Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, raw)
    pairs = URI.query_decoder(raw) |> Enum.to_list()

    Enum.all?(pairs, fn {key, value} -> key in allowed and String.valid?(value) end) and
      length(pairs) == length(Enum.uniq_by(pairs, &elem(&1, 0)))
  rescue
    _ -> false
  end
end
