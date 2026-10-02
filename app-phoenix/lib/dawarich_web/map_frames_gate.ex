defmodule DawarichWeb.MapFramesGate do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  alias Dawarich.{Entitlements, MapWindow}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.{LayoutAssigns, RailsAuth, Strangler}

  @month ~r/\A(19|20|21)\d{2}-(0[1-9]|1[0-2])\z/
  @types ["text/html", "application/xhtml+xml", "text/vnd.turbo-stream.html", "*/*"]

  def track?(conn, _params), do: plain?(conn, query(conn))

  def feed?(conn, _params) do
    query = query(conn)
    plain?(conn, query) and timestamp?(query["start_at"]) and timestamp?(query["end_at"])
  end

  defp timestamp?(value) when is_binary(value),
    do: Ruby.present?(value) and (value =~ ~r/\A\d+\z/ or MapWindow.iso?(value))

  defp timestamp?(_value), do: false

  def calendar?(conn, _params) do
    query = query(conn)
    plain?(conn, query) and month?(Map.get(query, "month")) and accept?(conn)
  end

  def residency?(conn, _params) do
    query = query(conn)
    plain?(conn, query) and year?(Map.get(query, "year")) and pro?(conn)
  end

  defp month?(nil), do: true
  defp month?(value) when is_binary(value), do: Ruby.blank?(value) or value =~ @month
  defp month?(_value), do: false

  defp accept?(conn) do
    accept = conn |> get_req_header("accept") |> Enum.join(", ")

    String.trim(accept) == "" or Strangler.browser_like?(accept) or
      (not String.contains?(accept, ";") and
         Enum.all?(String.split(accept, ","), &(String.trim(&1) in @types)))
  end

  defp year?(nil), do: true

  defp year?(value) when is_binary(value),
    do: value =~ ~r/\A\d{4}\z/ and String.to_integer(value) in 1970..2037

  defp year?(_value), do: false

  defp pro?(conn) do
    case RailsAuth.call(conn, []).assigns.current_user do
      nil ->
        true

      user ->
        LayoutAssigns.self_hosted?() or Entitlements.full_access?(user, false, DateTime.utc_now())
    end
  end

  defp query(conn), do: Plug.Conn.Query.decode(conn.query_string)

  defp plain?(conn, query),
    do:
      not Enum.any?(~w(locale client aff via), &Map.has_key?(query, &1)) and
        get_req_header(conn, "x-dawarich-client") == []
end
