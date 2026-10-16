defmodule DawarichWeb.AuthNavigation do
  @moduledoc false
  def sign_in(conn, opts, fallback) do
    if Keyword.get(opts, :native, false) and locale_query?(conn.query_string),
      do: DawarichWeb.AuthResponse.form(conn, "", nil, 200),
      else: fallback.(conn, opts)
  end

  def locale_query?(query) do
    case URI.query_decoder(query) |> Enum.to_list() do
      [{"locale", locale}] -> locale in Dawarich.Localization.locales()
      _ -> false
    end
  rescue
    _ -> false
  end
end
