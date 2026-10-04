defmodule Dawarich.Tags.Validation do
  @moduledoc false

  alias Dawarich.I18n
  alias Dawarich.RubyInteger
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @fields ~w(name icon color privacy_radius_meters)
  @defaults %{name: nil, icon: nil, color: nil, privacy_radius_meters: nil, demo: false}
  @number ~r/\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\z/

  def validate(repo, user, attrs, current \\ %{}, locale \\ "en") do
    with true <-
           Enum.all?(attrs, fn {key, value} ->
             key in @fields and is_binary(value) and String.valid?(value)
           end),
         tag <- Map.merge(@defaults, current),
         raw <- Map.get(attrs, "privacy_radius_meters", tag.privacy_radius_meters),
         {:ok, radius} <- cast(raw) do
      tag =
        Enum.reduce(attrs, tag, fn {key, value}, tag ->
          Map.put(tag, String.to_existing_atom(key), value)
        end)

      tag = %{tag | privacy_radius_meters: radius}

      errors =
        name_errors(repo, user.id, tag) ++
          icon_errors(tag.icon) ++ color_errors(tag.color) ++ radius_errors(raw, radius)

      %{valid: errors == [], tag: tag, raw_radius: raw, errors: messages(errors, locale)}
    else
      _ -> :rails
    end
  end

  defp cast(nil), do: {:ok, nil}
  defp cast(value) when is_integer(value), do: bounded(value)

  defp cast(value) when is_binary(value) do
    cond do
      Ruby.blank?(value) ->
        {:ok, nil}

      String.contains?(value, ["_", <<0>>]) or
          (Regex.match?(@number, Ruby.strip(value)) and
             not match?({_, ""}, Float.parse(Ruby.strip(value)))) ->
        :rails

      true ->
        bounded(RubyInteger.to_i(value))
    end
  end

  defp cast(_), do: :rails
  defp bounded(value) when value in -2_147_483_648..2_147_483_647, do: {:ok, value}
  defp bounded(_), do: :rails

  defp name_errors(repo, user_id, tag) do
    duplicate =
      repo.query!(
        "SELECT 1 FROM public.tags WHERE user_id = $1 AND name IS NOT DISTINCT FROM $2::varchar " <>
          "AND ($3::bigint IS NULL OR id != $3) LIMIT 1",
        [user_id, tag.name, Map.get(tag, :id)]
      ).rows != []

    [] |> add(Ruby.blank?(tag.name), :name, :blank) |> add(duplicate, :name, :taken)
  end

  defp icon_errors(icon) do
    if Ruby.blank?(icon) do
      []
    else
      []
      |> add(length(String.codepoints(icon)) > 10, :icon, :too_long, %{"count" => 10})
      |> add(Regex.match?(~r/\A[a-zA-Z]+\z/, icon), :icon, :ascii_icon)
    end
  end

  defp color_errors(color),
    do:
      add(
        [],
        not Ruby.blank?(color) and
          not Regex.match?(~r/\A#(?:[A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z/, color),
        :color,
        :invalid
      )

  defp radius_errors(_raw, nil), do: []

  defp radius_errors(raw, _radius) do
    case number(raw) do
      {:ok, value} ->
        []
        |> add(value <= 0, :privacy_radius_meters, :greater_than, %{"count" => 0})
        |> add(value > 5000, :privacy_radius_meters, :less_than_or_equal_to, %{"count" => 5000})

      :error ->
        [{:privacy_radius_meters, :not_a_number, %{}}]
    end
  end

  defp number(value) when is_integer(value), do: {:ok, value}

  defp number(value) when is_binary(value) do
    value = Ruby.strip(value)

    if Regex.match?(@number, value) do
      case Float.parse(value) do
        {number, ""} ->
          {:ok, number |> :erlang.float_to_binary(scientific: 14) |> String.to_float()}

        _ ->
          :error
      end
    else
      :error
    end
  end

  defp number(_), do: :error

  defp messages(errors, locale) do
    Enum.map(errors, fn {field, kind, bindings} ->
      key =
        if kind == :ascii_icon,
          do: "models.tag.must_be_an_emoji_or_symbol_not_a_letter",
          else: "errors.messages.#{kind}"

      {:ok, message} = I18n.t(locale, key, bindings)

      {:ok, full} =
        I18n.t(locale, "errors.format", %{
          "attribute" => attribute(locale, field),
          "message" => message
        })

      %{
        "attribute" => Atom.to_string(field),
        "type" => if(kind == :ascii_icon, do: message, else: Atom.to_string(kind)),
        "message" => full
      }
    end)
  end

  defp attribute(locale, field) do
    case I18n.t(locale, "activerecord.attributes.tag.#{field}") do
      {:ok, text} when is_binary(text) -> text
      _ -> field |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
    end
  end

  defp add(errors, condition, field, kind, bindings \\ %{})
  defp add(errors, true, field, kind, bindings), do: errors ++ [{field, kind, bindings}]
  defp add(errors, false, _, _, _), do: errors
end
