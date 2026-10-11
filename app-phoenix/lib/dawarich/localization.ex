defmodule Dawarich.Localization do
  @moduledoc false
  @locales ~w(en de es fr pl ca zh)
  def locales do
    @locales
  end

  def resolve(parameter, user, session) do
    exact(parameter) || preferred(user) || exact(session["locale"]) || "en"
  end

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

  def exact(value) when is_binary(value) do
    locale = String.downcase(value)

    if locale in @locales do
      locale
    end
  end

  def exact(_value) do
    nil
  end

  def preferred(user) do
    case Dawarich.UserSettings.value(user, "locale") do
      value when is_binary(value) ->
        locale = value |> String.trim() |> String.downcase()

        if locale in @locales do
          locale
        end

      _ ->
        nil
    end
  end

  defp present?(value) when is_binary(value) do
    String.trim(value) != ""
  end

  defp present?(value) when is_list(value) do
    value != []
  end

  defp present?(value) when is_map(value) do
    map_size(value) > 0
  end

  defp present?(value) do
    value not in [nil, false]
  end

  defp language(value) do
    locale = value |> String.trim() |> String.downcase() |> String.split("-") |> List.first()

    if locale in @locales do
      locale
    end
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
            ["q", value] -> ruby_to_f(value)
            _ -> nil
          end
        end)

      case language(language) do
        candidate when is_binary(candidate) and quality > 0 -> [{candidate, quality, index}]
        _ -> []
      end
    end)
  end

  defp candidates(_) do
    []
  end

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

  defp normalize_leading_dot("." <> rest) do
    "0." <> rest
  end

  defp normalize_leading_dot("-." <> rest) do
    "-0." <> rest
  end

  defp normalize_leading_dot("+." <> rest) do
    "+0." <> rest
  end

  defp normalize_leading_dot(number) do
    number
  end

  defp normalize_decimal_before_exponent(number) do
    String.replace(number, ~r/\.(?=[eE])/, ".0")
  end
end
