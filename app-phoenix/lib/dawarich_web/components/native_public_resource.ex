defmodule DawarichWeb.NativePublicResource do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{LocalizedDate, NumberFormat, TimeAgo}

  attr :presentation, :map, required: true
  attr :selected_day, :string, default: nil
  attr :locale, :string, required: true

  def resource(%{presentation: %{resource: nil}} = assigns), do: ~H""

  def resource(assigns) do
    data = assigns.presentation.resource
    assigns = assign(assigns, data: data, link: assigns.presentation.link, metrics: metrics(data))

    ~H"""
    <section id="native-public-resource" class="min-w-0 space-y-4 [overflow-wrap:anywhere]">
      <p>
        {DawarichWeb.MapParts.human_date(@locale, NaiveDateTime.to_date(@data.started_at.local))} – {DawarichWeb.MapParts.human_date(
          @locale,
          NaiveDateTime.to_date(@data.ended_at.local)
        )}
      </p>
      <div :if={@data.family} class="flex min-w-0 flex-wrap gap-2">
        <a href="/trips" class="btn btn-sm h-auto whitespace-normal">{t(
          @locale,
          "shared_links.family.back_to_trips",
          %{}
        )}</a>
        <a
          href={"/map/v2?" <> URI.encode_query(%{start_at: NaiveDateTime.to_iso8601(@data.started), end_at: NaiveDateTime.to_iso8601(@data.ended)})}
          class="btn btn-sm h-auto whitespace-normal"
        >{t(@locale, "shared_links.family.your_map", %{})}</a>
      </div>
      <DawarichWeb.TripParts.countries
        :if={@link.type == "trip" && @link.settings["show_stats"] == true}
        page={@data}
        locale={@locale}
      />
      <dl
        :if={@link.settings["show_stats"] == true}
        id="native-public-metrics"
        class="flex min-w-0 flex-wrap gap-4"
      >
        <div :for={{key, value} <- @metrics} class="min-w-0">
          <dt>{t(@locale, "shared.links.track." <> key, %{})}</dt>
          <dd class="font-semibold">{metric(@locale, key, value, @data.settings.unit)}</dd>
        </div>
      </dl>
      <div
        :if={@data[:description] not in [nil, ""]}
        id="native-public-description"
        class="prose max-w-none min-w-0 [overflow-wrap:anywhere]"
      >
        <h2>{t(@locale, "shared.links.trip.trip_notes", %{})}</h2>
        {Phoenix.HTML.raw(Dawarich.TripDescription.html(@data.description))}
      </div>
      <details
        :for={day <- @data.days}
        data-public-day={to_string(day.date)}
        data-public-day-selected={to_string(@selected_day == to_string(day.date))}
        class="min-w-0 rounded-lg bg-base-200 p-3"
        phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
      >
        <summary class="flex min-w-0 flex-wrap items-center gap-2">
          {LocalizedDate.l(@locale, day.date, "day_month_year_abbreviated")}
          <button
            :if={@link.settings["show_route"] != false}
            type="button"
            class="btn btn-xs h-auto whitespace-normal"
            phx-click="public:day"
            phx-value-day={to_string(day.date)}
            aria-pressed={to_string(@selected_day == to_string(day.date))}
          >{t(@locale, "map.timeline_feeds.day.select", %{})}</button>
          <span :if={day.stats}>{Calendar.strftime(day.stats.first, "%H:%M")} – {Calendar.strftime(
            day.stats.last,
            "%H:%M"
          )} · {metric(@locale, "distance", day.stats.distance, @data.settings.unit)}</span>
          <span :if={!day.stats}>{t(@locale, "shared.links.trip.no_data", %{})}</span>
        </summary>
        <p :if={day.note} class="whitespace-pre-wrap min-w-0 [overflow-wrap:anywhere]">
          {day.note.body}
        </p>
        <div class="grid grid-cols-3 gap-2 min-w-0">
          <img
            :for={photo <- day.photos}
            src={"/native/public/maps/#{@link.id}/photos/#{URI.encode_www_form(photo["id"])}/thumbnail?" <> URI.encode_query(%{source: photo["source"]})}
            loading="lazy"
            alt=""
            class="w-full aspect-square rounded-lg object-cover"
          />
        </div>
      </details>
    </section>
    """
  end

  defp metrics(data) do
    [
      {"distance", data[:distance]},
      {"duration", data[:track_duration]},
      {"avg_speed", data[:speed]},
      {"elevation_gain", data[:gain]},
      {"elevation_loss", data[:loss]}
    ]
    |> Enum.filter(fn {_key, value} -> is_number(value) && value > 0 end)
  end

  defp metric(locale, "distance", value, unit),
    do:
      "#{NumberFormat.with_precision_one(locale, Dawarich.Distance.convert(value, unit) * 1.0)} #{unit}"

  defp metric(locale, "duration", value, _unit),
    do:
      TimeAgo.words(
        locale,
        ~N[2000-01-01 00:00:00],
        NaiveDateTime.add(~N[2000-01-01 00:00:00], value)
      )

  defp metric(locale, "avg_speed", value, unit),
    do:
      t(locale, if(unit == "mi", do: "units.speed_mph", else: "units.speed_kmh"), %{
        value:
          NumberFormat.with_precision_one(
            locale,
            value * if(unit == "mi", do: 0.621371, else: 1) * 1.0
          )
      })

  defp metric(locale, _key, value, _unit), do: t(locale, "units.meters", %{value: round(value)})
end
