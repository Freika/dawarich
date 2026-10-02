defmodule DawarichWeb.Locale do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias DawarichWeb.RailsSession

  @locales ~w(en de es fr pl ca zh)

  def init(opts), do: opts

  def locales, do: @locales

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

  def resolve(parameter, user, session),
    do: exact(parameter) || preferred(user) || exact(session["locale"]) || "en"

  def suggest(header, parameter, user, session, locale) do
    if present?(parameter) or preferred(user) != nil or present?(session["locale"]) do
      nil
    else
      header
      |> candidates()
      |> Enum.max_by(fn {_language, quality, index} -> {quality, -index} end, fn -> nil end)
      |> case do
        {candidate, _quality, _index} when candidate != locale -> candidate
        _ -> nil
      end
    end
  end

  defp remember(conn, nil), do: conn

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
    if preferred(user) == locale,
      do: conn,
      else:
        assign(conn, :current_user, %{
          user
          | settings: Dawarich.Accounts.persist_locale(id, locale)
        })
  end

  defp persist(conn, _locale), do: conn

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

  defp header(conn, name), do: conn |> get_req_header(name) |> Enum.join(", ")

  defp exact(value) when is_binary(value) do
    locale = String.downcase(value)
    if locale in @locales, do: locale
  end

  defp exact(_value), do: nil

  defp preferred(%{settings: %{"locale" => value}}) when is_binary(value) do
    locale = value |> String.trim() |> String.downcase()
    if locale in @locales, do: locale
  end

  defp preferred(_user), do: nil

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value), do: value != []
  defp present?(value) when is_map(value), do: map_size(value) > 0
  defp present?(value), do: value not in [nil, false]

  defp language(value) do
    locale = value |> String.trim() |> String.downcase() |> String.split("-") |> List.first()
    if locale in @locales, do: locale
  end

  defp candidates(header) when is_binary(header) do
    header
    |> String.split(",")
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, index} ->
      [language | parameters] = entry |> String.split(";") |> Enum.map(&String.trim/1)

      quality =
        parameters
        |> Enum.find_value(1.0, fn parameter ->
          case String.split(parameter, "=", parts: 2) do
            ["q", value] ->
              ruby_to_f(value)

            _ ->
              nil
          end
        end)

      case language(language) do
        candidate when is_binary(candidate) and quality > 0 -> [{candidate, quality, index}]
        _ -> []
      end
    end)
  end

  defp candidates(_), do: []

  def ruby_to_f(value) do
    case Regex.run(
           ~r/^\s*([+-]?(?:\d+(?:_\d+)*(?:\.\d*(?:_\d+)*)?|\.\d+(?:_\d+)*)(?:[eE][+-]?\d+(?:_\d+)*)?)/,
           value
         ) do
      [_, number] ->
        case Float.parse(
               number
               |> normalize_leading_dot()
               |> normalize_decimal_before_exponent()
               |> String.replace("_", "")
             ) do
          {parsed, _rest} -> parsed
          :error -> 0.0
        end

      _ ->
        0.0
    end
  end

  defp normalize_leading_dot("." <> rest), do: "0." <> rest
  defp normalize_leading_dot("-." <> rest), do: "-0." <> rest
  defp normalize_leading_dot("+." <> rest), do: "+0." <> rest
  defp normalize_leading_dot(number), do: number

  defp normalize_decimal_before_exponent(number), do: String.replace(number, ~r/\.(?=[eE])/, ".0")
end
