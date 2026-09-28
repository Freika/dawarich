defmodule DawarichWeb.Locale do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    parameter = conn.params["locale"]
    user = conn.assigns[:current_user]
    session = conn.assigns[:rails_session] || %{}
    locale = resolve(parameter, user, session)

    assign(conn, :locale, locale)
    |> assign(
      :suggested_locale,
      suggest(
        get_req_header(conn, "accept-language") |> List.first(),
        parameter,
        user,
        session,
        locale
      )
    )
  end

  def resolve(parameter, user, session) do
    supported(parameter) || preferred(user) || supported(session["locale"]) || "en"
  end

  def suggest(header, parameter, user, session, locale) do
    if parameter || preferred(user) || supported(session["locale"]) do
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

  defp preferred(%{settings: settings}) when is_map(settings), do: supported(settings["locale"])
  defp preferred(_), do: nil

  defp supported(value) when is_binary(value) do
    locale = value |> String.trim() |> String.downcase() |> String.split("-") |> List.first()
    if locale in ~w(ca de en es fr pl zh), do: locale
  end

  defp supported(_), do: nil

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

      case supported(language) do
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
