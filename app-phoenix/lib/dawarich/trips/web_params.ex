defmodule Dawarich.Trips.WebParams do
  @moduledoc false
  alias Dawarich.{I18n, MapWindow, RailsTime, Repo, TimeZoneName, UserTimeZone}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Trips.WebDescription
  alias Dawarich.Imports.ImportTime

  @local ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,6})?)?\z/
  @iso ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})\z/

  def parse(%{} = user, %{} = attrs, previous, context) do
    settings = Dawarich.UserSettings.get(user)
    repo = Map.get(context, :repo, Repo)
    zone = UserTimeZone.zone(settings)
    zone = if Ruby.blank?(zone), do: System.get_env("TIME_ZONE", "UTC"), else: zone

    if is_map(settings) and is_binary(zone) and
         (is_nil(settings["timezone"]) or is_binary(settings["timezone"])) do
      RailsTime.with_zone(repo, zone, fn ->
        cast(
          repo,
          TimeZoneName.to_iana(zone),
          attrs,
          previous,
          Map.get(context, :locale, "en"),
          Map.get(context, :now, DateTime.utc_now())
        )
      end)
    else
      {:replay, "trip time zone shape"}
    end
  end

  def parse(_user, _attrs, _previous, _context), do: {:replay, "trip settings or attributes"}

  defp cast(repo, zone, attrs, previous, locale, now) do
    with {:ok, name} <- name(attrs, previous),
         {:ok, started} <- date(repo, zone, attrs, previous, "started_at", now),
         {:ok, ended} <- date(repo, zone, attrs, previous, "ended_at", now),
         {:ok, description} <-
           WebDescription.prepare(
             Map.get(attrs, "description", :omitted),
             previous[:description],
             repo
           ) do
      values = %{name: name, started_at: started, ended_at: ended, description: description}
      errors = errors(values, locale)

      if errors == [] do
        {:ok, values}
      else
        {:invalid, errors,
         %{
           raw: attrs,
           attributes: values,
           values: %{
             "name" => name,
             "started_at" => display(repo, zone, started),
             "ended_at" => display(repo, zone, ended)
           }
         }}
      end
    end
  end

  defp name(attrs, previous) do
    case Map.get(attrs, "name", previous[:name]) do
      value when is_binary(value) or is_nil(value) -> {:ok, value}
      _ -> {:replay, "trip name shape"}
    end
  end

  defp date(repo, zone, attrs, previous, key, now) do
    case Map.fetch(attrs, key) do
      :error -> {:ok, previous[String.to_existing_atom(key)]}
      {:ok, nil} -> {:ok, nil}
      {:ok, raw} when is_binary(raw) -> stamp(repo, zone, raw, now)
      _ -> {:replay, "trip date shape"}
    end
  end

  defp stamp(repo, zone, raw, now) do
    cond do
      Ruby.blank?(raw) or raw == "not-a-date" ->
        {:ok, nil}

      Regex.match?(@local, raw) ->
        raw = if byte_size(raw) == 16, do: raw <> ":00", else: raw

        case NaiveDateTime.from_iso8601(raw) do
          {:ok, naive} -> {:ok, MapWindow.local_utc(naive, zone, repo)}
          _ -> fallback(repo, zone, raw, now)
        end

      Regex.match?(@iso, raw) ->
        case DateTime.from_iso8601(raw) do
          {:ok, at, _} -> {:ok, DateTime.to_naive(at)}
          _ -> fallback(repo, zone, raw, now)
        end

      true ->
        fallback(repo, zone, raw, now)
    end
  end

  defp fallback(repo, zone, raw, now) do
    case ImportTime.parse(raw, zone, now, repo) do
      nil ->
        {:ok, nil}

      seconds ->
        parts = Dawarich.Imports.DateParts.parse(raw)
        {n, d} = rational(parts["sec_fraction"])
        {offset, scale} = rational(parts["offset"])
        fraction = Integer.floor_div((n * scale - offset * d) * 1_000_000, d * scale)

        at =
          DateTime.from_unix!(
            seconds * 1_000_000 + Integer.mod(fraction, 1_000_000),
            :microsecond
          )

        {:ok, DateTime.to_naive(at)}
    end
  rescue
    ArgumentError -> {:ok, nil}
  end

  defp rational(%{"numerator" => n, "denominator" => d}), do: {n, d}
  defp rational(value) when is_integer(value), do: {value, 1}
  defp rational(_), do: {0, 1}

  defp display(_repo, _zone, nil), do: nil

  defp display(repo, zone, at) do
    [[local]] =
      repo.query!("SELECT ($1::timestamp AT TIME ZONE 'UTC') AT TIME ZONE $2", [at, zone]).rows

    Calendar.strftime(local, "%Y-%m-%dT%H:%M")
  end

  defp errors(values, locale) do
    fields = ~w(name started_at ended_at)a

    presence =
      for field <- fields,
          Ruby.blank?(values[field]),
          do: error(locale, field, "errors.messages.blank")

    if values.started_at && values.ended_at &&
         NaiveDateTime.compare(values.started_at, values.ended_at) != :lt,
       do: presence ++ [error(locale, :ended_at, "models.trip.must_be_after_start_date")],
       else: presence
  end

  defp error(locale, field, key) do
    attribute =
      case I18n.t(locale, "activerecord.attributes.trip.#{field}") do
        {:ok, text} when is_binary(text) -> text
        _ -> field |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
      end

    {:ok, message} = I18n.t(locale, key)

    {:ok, full} =
      I18n.t(locale, "errors.format", %{"attribute" => attribute, "message" => message})

    {Atom.to_string(field), full}
  end
end
