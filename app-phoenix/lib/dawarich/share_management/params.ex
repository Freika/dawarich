defmodule Dawarich.ShareManagement.Params do
  @moduledoc false

  alias Dawarich.{I18n, UserTimeZone}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @settings ~w(show_photos show_stats show_route show_countries show_description show_days show_day_notes)
  @false_values [false, 0, "0", "f", "F", "false", "FALSE", "off", "OFF"]
  @top ~w(shared_link authenticity_token commit hub start_date end_date)

  def create(user, type, trip, params, locale) do
    if supported?(user, type, trip, params),
      do: attributes(user, type, trip, params, locale),
      else: :rails
  end

  defp supported?(user, type, trip, params) do
    raw = if is_map(params), do: Map.get(params, "shared_link", %{})

    type in ["live", "trip"] and (type == "live" or (is_map(trip) and is_integer(trip[:id]))) and
      is_map(user.settings) and text?(user.settings["timezone"]) and is_map(params) and
      Enum.all?(params, fn {key, value} ->
        key in @top and (key == "shared_link" or text?(value))
      end) and
      is_map(raw) and Enum.all?(~w(name magic_phrase expires_at), &text?(raw[&1])) and
      date_shape?(raw["expires_at"]) and settings?(raw["settings"])
  end

  def date_shape?(nil), do: true

  def date_shape?(raw) when is_binary(raw),
    do: raw =~ ~r/\A\d{4}-\d{2}-\d{2}\z/ or not (raw =~ ~r/\d/)

  def date_shape?(_raw), do: false

  defp settings?(nil), do: true
  defp settings?(value) when value in [false, "", []], do: true

  defp settings?(%{} = raw),
    do: Enum.all?(Map.take(raw, @settings), fn {_key, value} -> scalar?(value) end)

  defp settings?(_raw), do: false

  defp scalar?(value),
    do: is_nil(value) or is_binary(value) or is_boolean(value) or is_number(value)

  defp text?(value), do: is_nil(value) or is_binary(value)

  defp attributes(user, type, trip, params, locale) do
    raw = Map.get(params, "shared_link", %{})
    settings = if Ruby.blank?(raw["settings"]), do: %{}, else: raw["settings"]

    defaults =
      if type == "live",
        do: %{"show_photos" => false, "show_route" => false},
        else: %{"show_photos" => false, "show_stats" => false}

    name = if Ruby.blank?(raw["name"]), do: default_name(type, trip, locale), else: raw["name"]

    {:ok,
     %{
       user_id: user.id,
       resource_type: if(type == "live", do: 3, else: 0),
       resource_id: if(trip, do: trip.id),
       name: name,
       magic_phrase: if(Ruby.blank?(raw["magic_phrase"]), do: nil, else: raw["magic_phrase"]),
       expires_at: expiry_from(raw["expires_at"], user.settings),
       settings:
         Map.merge(
           defaults,
           settings
           |> Map.take(@settings)
           |> Map.new(fn {key, value} -> {key, boolean(value)} end)
         )
     }}
  end

  def validate(attrs, now, locale, opts \\ []) do
    original = Keyword.get(opts, :original)
    expiry_changed? = is_nil(original) or attrs.expires_at != original.expires_at

    [
      {Ruby.blank?(attrs.name), :name, "errors.messages.blank", %{}},
      {codepoints(attrs.name) > 255, :name, "errors.messages.too_long", %{"count" => 255}},
      {codepoints(attrs.magic_phrase) > 255, :magic_phrase, "errors.messages.too_long",
       %{"count" => 255}},
      {expiry_changed? and not is_nil(attrs.expires_at) and
         NaiveDateTime.compare(attrs.expires_at, DateTime.to_naive(now)) != :gt, :expires_at,
       "models.shared_link.must_be_in_the_future", %{}}
    ]
    |> Enum.flat_map(fn
      {true, field, key, bindings} -> [{field, full_message(locale, field, key, bindings)}]
      _ -> []
    end)
  end

  defp full_message(locale, field, key, bindings) do
    attribute =
      case I18n.t(locale, "activerecord.attributes.shared_link.#{field}") do
        {:ok, text} when is_binary(text) -> text
        _ -> field |> to_string() |> String.replace("_", " ") |> String.capitalize()
      end

    {:ok, message} = I18n.t(locale, key, bindings)

    {:ok, full} =
      I18n.t(locale, "errors.format", %{"attribute" => attribute, "message" => message})

    full
  end

  defp codepoints(nil), do: 0
  defp codepoints(text), do: text |> String.codepoints() |> length()

  defp default_name("live", _trip, locale) do
    {:ok, name} = I18n.t(locale, "controllers.share_links.lives.default_name")
    name
  end

  defp default_name("trip", trip, locale) do
    {:ok, name} =
      I18n.t(locale, "controllers.trips.share_links.default_name", %{"trip" => trip.name})

    name
  end

  defp boolean(value) when value in [nil, ""], do: nil
  defp boolean(value), do: value not in @false_values

  def expiry_from(raw, settings) do
    case date(raw) do
      nil -> nil
      date -> midnight(date, settings)
    end
  end

  defp midnight(date, settings) do
    %{rows: [[at]]} =
      UserTimeZone.query!(
        """
        , base AS (SELECT $1::date::timestamp AS wall, z.name,
                          $1::date::timestamp AT TIME ZONE z.name AS utc FROM z),
          candidates AS (
            SELECT wall, name, utc,
                   wall - ((t AT TIME ZONE name) - (t AT TIME ZONE 'UTC')) AS candidate
            FROM base, LATERAL (VALUES (utc - interval '1 day'), (utc), (utc + interval '1 day')) AS offsets(t)
          )
        SELECT coalesce(min(candidate) FILTER (
          WHERE (candidate AT TIME ZONE 'UTC') AT TIME ZONE name = wall),
          min(utc AT TIME ZONE 'UTC')) FROM candidates
        """,
        [date],
        settings
      )

    NaiveDateTime.truncate(at, :second)
  end

  defp date(raw) when is_binary(raw) do
    case Date.from_iso8601(raw) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp date(_raw), do: nil
end
