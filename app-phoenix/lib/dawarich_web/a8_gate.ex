defmodule DawarichWeb.A8Gate do
  @moduledoc false
  alias Dawarich.Visits.WebSettings
  alias DawarichWeb.{RailsAuth, Strangler}

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
