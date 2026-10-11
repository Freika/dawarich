defmodule DawarichWeb.Locale do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  import Dawarich.Localization, only: [exact: 1, preferred: 1]
  alias DawarichWeb.RailsSession

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    parameter = conn.params["locale"]
    conn = remember(conn, exact(parameter))
    user = conn.assigns[:current_user]
    session = conn.assigns[:rails_session] || %{}
    locale = resolve(parameter, user, session)
    header = get_req_header(conn, "accept-language") |> List.first()

    conn
    |> assign(:locale, locale)
    |> assign(:suggested_locale, suggest(header, parameter, user, session, locale))
  end

  defp remember(conn, nil) do
    conn
  end

  defp remember(conn, locale) do
    if chosen_by_reader?(conn) do
      session = Map.put(conn.assigns[:rails_session] || %{}, "locale", locale)

      conn
      |> RailsSession.stage(%{"locale" => locale})
      |> assign(:rails_session, session)
      |> persist(locale)
    else
      conn
    end
  end

  defp persist(%{assigns: %{current_user: %{id: id} = user}} = conn, locale) do
    if preferred(user) == locale do
      conn
    else
      case Dawarich.Accounts.persist_locale(id, locale) do
        {:ok, settings} -> assign(conn, :current_user, %{user | settings: settings})
        {:error, :unsupported} -> conn
      end
    end
  end

  defp persist(conn, _locale) do
    conn
  end

  defp chosen_by_reader?(conn) do
    purposes = [
      header(conn, "sec-purpose"),
      header(conn, "x-sec-purpose"),
      header(conn, "purpose")
    ]

    not Enum.any?(purposes, &String.contains?(&1, "prefetch")) and
      String.downcase(header(conn, "x-moz")) != "prefetch" and
      header(conn, "sec-fetch-site") != "cross-site"
  end

  defp header(conn, name) do
    conn |> get_req_header(name) |> Enum.join(", ")
  end

  defdelegate locales(), to: Dawarich.Localization
  defdelegate resolve(arg1, arg2, arg3), to: Dawarich.Localization
  defdelegate suggest(arg1, arg2, arg3, arg4, arg5), to: Dawarich.Localization
  defdelegate ruby_to_f(arg1), to: Dawarich.Localization
end
