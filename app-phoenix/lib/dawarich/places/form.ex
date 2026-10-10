defmodule Dawarich.Places.Form do
  @moduledoc false
  import Ecto.Changeset
  alias Dawarich.Places.{WebWrite, WebTags}

  @types %{
    name: :string,
    latitude: :string,
    longitude: :string,
    source: :string,
    note: :string,
    tag_ids: {:array, :string}
  }
  @sources %{"manual" => 0, "photon" => 1, "gpx_waypoint" => 2, nil => nil, "" => nil}

  def new,
    do: %{name: nil, latitude: nil, longitude: nil, source: "manual", note: nil, tag_ids: []}

  def initial(data) do
    cast({data(data), @types}, %{}, Map.keys(@types), empty_values: [])
  end

  def change(data, attrs, locale) do
    changeset = cast({data(data), @types}, normalize(attrs), Map.keys(@types), empty_values: [])
    errors = shape_errors(attrs, locale)
    previous = if data[:id], do: stored(data), else: nil
    action = if previous, do: :update, else: :create

    errors =
      case WebWrite.values(action, previous, attrs) do
        {:ok, values} ->
          errors ++ WebWrite.validation_errors(values, locale)

        _ ->
          errors ++
            coordinate_errors(attrs, locale) ++
            WebWrite.validation_errors(
              %{name: get_field(changeset, :name), latitude: 0, longitude: 0},
              locale
            )
      end

    Enum.reduce(Enum.uniq(errors), changeset, fn
      {"lonlat", message}, cs ->
        cs |> add_error(:latitude, message) |> add_error(:longitude, message)

      {field, message}, cs ->
        add_error(cs, String.to_existing_atom(field), message)
    end)
  end

  defp shape_errors(attrs, locale) when is_map(attrs) do
    errors =
      for key <- ~w(name note),
          Map.has_key?(attrs, key),
          not (is_binary(attrs[key]) or is_nil(attrs[key])),
          do: invalid(locale, key)

    errors =
      if Map.has_key?(attrs, "source") and not Map.has_key?(@sources, attrs["source"]),
        do: errors ++ [invalid(locale, "source")],
        else: errors

    if WebTags.supported?(attrs), do: errors, else: errors ++ [invalid(locale, "tag_ids")]
  end

  defp shape_errors(_, locale), do: [invalid(locale, "name")]

  defp coordinate_errors(attrs, locale) when is_map(attrs) do
    for {key, limit} <- [{"latitude", 90}, {"longitude", 180}],
        Map.has_key?(attrs, key) and WebWrite.coordinate(attrs[key], limit) in [:unsupported, nil],
        do: invalid(locale, key)
  end

  defp coordinate_errors(_, _), do: []

  defp invalid(locale, key),
    do: {key, Dawarich.WebValidation.message(locale, "place", key, "errors.messages.invalid")}

  defp normalize(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {"tag_ids", values} when is_list(values) -> {"tag_ids", Enum.map(values, &text/1)}
      {key, value} when is_number(value) -> {key, to_string(value)}
      pair -> pair
    end)
  end

  defp normalize(_), do: %{}
  defp text(v) when is_number(v), do: to_string(v)
  defp text(v), do: v

  defp data(current),
    do:
      Map.new(@types, fn {field, _} ->
        {field,
         if(field == :tag_ids,
           do: Enum.map(current[field] || [], &text/1),
           else: text(current[field])
         )}
      end)

  defp stored(current),
    do:
      current
      |> Map.put(:source, Map.get(@sources, current[:source]))
      |> Map.merge(%{
        latitude: number(current[:latitude]),
        longitude: number(current[:longitude])
      })

  defp number(value) when is_binary(value) do
    case Float.parse(value) do
      {v, ""} -> v
      _ -> nil
    end
  end

  defp number(value), do: value
end
