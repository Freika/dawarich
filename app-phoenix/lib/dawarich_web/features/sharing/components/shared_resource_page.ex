defmodule DawarichWeb.SharedResourcePage do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{LocalizedDate, MapParts}
  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.MapReplay, only: [replay_panel: 1]
  import DawarichWeb.TripParts, only: [countries: 1]
  embed_templates "shared_resource_page/*"

  attr :locale, :string, required: true
  attr :link, :map, required: true
  attr :resource, :map, required: true

  attr :native, :boolean, default: false

  attr :map_config, :map, default: nil
  attr :selected_day, :string, default: nil
  attr :gallery_days, :any, default: MapSet.new()

  def resource(assigns) do
    ~H"""
    <.trip
      :if={@link.type == "trip"}
      locale={@locale}
      link={@link}
      resource={@resource}
      native={@native}
      live={not is_nil(@map_config)}
      map_config={@map_config}
      selected_day={@selected_day}
      gallery_days={@gallery_days}
    />
    <.track
      :if={@link.type == "track"}
      locale={@locale}
      link={@link}
      resource={@resource}
      native={@native}
      live={not is_nil(@map_config)}
      map_config={@map_config}
      selected_day={@selected_day}
      gallery_days={@gallery_days}
    />
    """
  end

  defp wrapper(_link, _resource, true), do: %{}

  defp wrapper(link, resource, false) do
    if link.settings["show_route"] != false do
      %{
        "data-controller" => "shared-trip-map",
        "data-shared-trip-map-link-id-value" => link.id,
        "data-shared-trip-map-show-photos-value" =>
          to_string(link.settings["show_photos"] == true),
        "data-shared-trip-map-by-day-value" => "true",
        "data-shared-trip-map-timezone-value" => resource.zone,
        "data-shared-trip-map-meters-between-routes-value" => resource.settings.meters,
        "data-shared-trip-map-minutes-between-routes-value" => resource.settings.minutes
      }
    else
      %{}
    end
  end

  defp row_data(link, day, gallery, true) do
    data =
      if link.settings["show_route"] != false,
        do: %{"data-public-day" => to_string(day.date)},
        else: %{}

    if gallery,
      do:
        Map.merge(data, %{
          "data-public-gallery" => true,
          "data-public-gallery-day" => to_string(day.date)
        }),
      else: data
  end

  defp row_data(link, day, gallery, false) do
    data =
      if link.settings["show_route"] != false do
        %{
          "data-day-key" => to_string(day.date),
          "data-action" =>
            "mouseenter->shared-trip-map#hoverDay mouseleave->shared-trip-map#leaveDay click->shared-trip-map#toggleDay",
          "data-shared-trip-map-day-key-param" => to_string(day.date)
        }
      else
        %{}
      end

    if gallery,
      do:
        Map.merge(data, %{
          "data-controller" => "lazy-gallery",
          "data-action" =>
            String.trim((data["data-action"] || "") <> " toggle->lazy-gallery#toggle")
        }),
      else: data
  end

  defp interaction(link, day, gallery, native, false, _selected),
    do: row_data(link, day, gallery, native)

  defp interaction(link, day, gallery, native, true, selected) do
    data = row_data(link, day, gallery, native)

    data =
      Map.merge(data, %{
        "id" => "native-public-day-#{day.date}",
        "data-public-day" => to_string(day.date),
        "data-public-day-selected" => to_string(selected == to_string(day.date))
      })

    data = if gallery, do: Map.put(data, "phx-hook", "PublicGallery"), else: data

    data =
      if gallery,
        do: Map.put(data, "phx-mounted", Phoenix.LiveView.JS.ignore_attributes("open")),
        else: data

    if link.settings["show_route"] != false,
      do:
        Map.merge(
          data,
          %{
            "phx-click" => "public:day",
            "phx-value-day" => to_string(day.date)
          }
          |> Map.merge(
            if gallery,
              do: %{},
              else: %{
                "role" => "button",
                "tabindex" => "0",
                "phx-keydown" => "public:day",
                "phx-key" => "Enter"
              }
          )
        ),
      else: data
  end

  defp public_number(value),
    do: value |> Kernel.*(1.0) |> Dawarich.RubyFloat.round(1) |> Float.to_string()

  defp distance(value, unit) do
    number = Dawarich.Distance.convert(value || 0, unit)

    if number < 1,
      do: "< 1 #{unit}",
      else: "#{DawarichWeb.NumberFormat.with_precision_one("en", number * 1.0)} #{unit}"
  end

  defp track_label(locale, resource) do
    mode =
      if resource.mode,
        do:
          t(
            locale,
            "transportation_modes." <>
              Dawarich.Transportation.Segments.int_to_mode(resource.mode),
            %{}
          ),
        else: t(locale, "helpers.shared_links.track", %{})

    t(locale, "helpers.shared_links.track_label", %{
      mode: mode,
      date:
        LocalizedDate.l(
          locale,
          NaiveDateTime.to_date(resource.started_at.local),
          "day_month_year_abbreviated"
        ),
      distance: round(Dawarich.Distance.convert(resource.distance || 0, resource.settings.unit)),
      unit: resource.settings.unit
    })
  end

  defp s(locale, key), do: t(locale, "shared.links.trip." <> key, %{})
end
