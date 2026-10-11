defmodule DawarichWeb.NativePublicContent do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{NativeChart, StatsFormat, LocalizedDate}
  attr :locale, :string, required: true
  attr :link, :map, required: true
  attr :resource, :map, required: true
  slot :map

  def resource(assigns) do
    ~H"""
    <section class="min-w-0 p-4" style="overflow-wrap:anywhere">
      <h1 class="text-3xl font-bold">{@resource.name || @link.name}</h1>
      <p>
        {LocalizedDate.l(@locale, NaiveDateTime.to_date(@resource.started_at), "medium")} – {LocalizedDate.l(
          @locale,
          NaiveDateTime.to_date(@resource.ended_at),
          "medium"
        )}
      </p>
      <p :if={@resource.distance}>{distance(@locale, @resource.distance, @resource.unit)}</p>
      <p :for={country <- @resource.countries}>{country}</p>
      <dl class="flex flex-wrap gap-4 min-w-0">
        <div :if={@resource[:track_duration] && @resource.track_duration > 0}>
          <dt>{t(@locale, "shared.links.track.duration", %{})}</dt>
          <dd>
            {DawarichWeb.TimeAgo.words(
              @locale,
              ~N[2000-01-01 00:00:00],
              NaiveDateTime.add(~N[2000-01-01 00:00:00], @resource.track_duration)
            )}
          </dd>
        </div>
        <div :if={@resource[:speed]}>
          <dt>{t(@locale, "shared.links.track.avg_speed", %{})}</dt>
          <dd>
            {t(@locale, if(@resource.unit == "mi", do: "units.speed_mph", else: "units.speed_kmh"), %{
              value:
                DawarichWeb.NumberFormat.with_precision_one(
                  @locale,
                  @resource.speed * if(@resource.unit == "mi", do: 0.621371, else: 1) * 1.0
                )
            })}
          </dd>
        </div>
        <div
          :for={
            {key, value} <- [
              {"elevation_gain", @resource[:gain]},
              {"elevation_loss", @resource[:loss]}
            ]
          }
          :if={value && value > 0}
        >
          <dt>{t(@locale, "shared.links.track." <> key, %{})}</dt><dd>
            {t(@locale, "units.meters", %{value: round(value)})}
          </dd>
        </div>
      </dl>
      {render_slot(@map)}
      <div :if={is_binary(@resource.description)} class="trix-content">
        {Phoenix.HTML.raw(@resource.description)}
      </div>
      <section :for={day <- @resource.days} class="min-w-0 py-3">
        <h2>{LocalizedDate.l(@locale, day.date, "long")}</h2>
        <p :if={day.stats}>{distance(@locale, day.stats.distance, @resource.unit)}</p>
        <p :if={day.note} class="whitespace-pre-wrap">{day.note}</p>
      </section>
      <div class="grid grid-cols-3 gap-2 min-w-0">
        <img
          :for={photo <- @resource.photos}
          src={photo["thumbnail_url"]}
          loading="lazy"
          alt=""
          class="w-full min-w-0"
        />
      </div>
      <a
        :if={@resource.next_cursor}
        rel="next"
        href={"/s/#{@link.id}?cursor=#{@resource.next_cursor}"}
      >{t(@locale, "achievements.ui.next_page", %{})}</a>
    </section>
    """
  end

  defp distance(locale, meters, unit),
    do:
      DawarichWeb.NumberFormat.with_precision_one(
        locale,
        Dawarich.Distance.convert(meters, unit) * 1.0
      ) <> " " <> unit

  attr :locale, :string, required: true
  attr :link, :map, required: true
  attr :error, :any, default: nil
  attr :rails_session, :map, required: true

  def prompt(assigns) do
    ~H"""
    <section class="hero min-h-[60vh] min-w-0">
      <div class="hero-content text-center min-w-0">
        <div class="max-w-md min-w-0" style="overflow-wrap:anywhere">
          <h1 class="text-3xl font-bold">
            {t(@locale, "shared.links.phrase_prompt.enter_the_magic_phrase", %{})}
          </h1>
          <p class="py-4">
            {t(
              @locale,
              "shared.links.phrase_prompt.this_shared_link_is_protected_ask_the_owner_for_the",
              %{}
            )}
          </p>
          <p :if={@error} role="alert" class="alert flex flex-wrap">{@error}</p>
          <form action={"/s/#{@link.id}/unlock"} method="post" class="min-w-0">
            <input
              type="hidden"
              name="authenticity_token"
              value={DawarichWeb.SharedPages.form_token(@rails_session, @link.id)}
            />
            <label for="public-phrase">{t(@locale, "shared.links.phrase_prompt.magic_phrase", %{})}</label>
            <input
              id="public-phrase"
              name="phrase"
              type="text"
              required
              autofocus
              class="input input-bordered w-full min-w-0"
            />
            <button class="btn btn-primary mt-4 whitespace-normal">{t(
              @locale,
              "shared.links.phrase_prompt.unlock",
              %{}
            )}</button>
          </form>
        </div>
      </div>
    </section>
    """
  end

  attr :locale, :string, required: true
  attr :page, :map, required: true
  slot :map

  def month(assigns) do
    assigns =
      assigns
      |> assign(:visited, Dawarich.Stats.Toponyms.visited(assigns.page.stat.toponyms))
      |> assign(:peak, StatsFormat.peak(assigns.page.stat.daily))

    ~H"""
    <section class="min-w-0 p-4" style="overflow-wrap:anywhere">
      <h1 class="text-3xl font-bold">
        {LocalizedDate.l(@locale, Date.new!(@page.stat.year, @page.stat.month, 1), "month_year")}
      </h1>
      <p>{t(@locale, "stats.public_month.monthly_digest", %{})}</p>
      <dl class="flex flex-wrap gap-4 min-w-0">
        <div class="min-w-0">
          <dt class="stat-title">{t(@locale, "stats.public_month.distance_traveled", %{})}</dt>
          <dd class="stat-value">{StatsFormat.distance(@locale, @page.stat.distance, @page.unit)}</dd>
        </div>
        <div class="min-w-0">
          <dt class="stat-title">{t(@locale, "stats.public_month.active_days", %{})}</dt>
          <dd class="stat-value">{StatsFormat.active_days(@page.stat.daily)}</dd>
        </div>
        <div class="min-w-0">
          <dt class="stat-title">{t(@locale, "stats.public_month.countries_visited", %{})}</dt>
          <dd class="stat-value">{length(@visited)}</dd>
        </div>
      </dl>
      <p :if={@page.stat.flight_distance > 0}>
        {t(@locale, "stats.public_month.flight_distance", %{})}: {StatsFormat.distance(
          @locale,
          @page.stat.flight_distance,
          @page.unit
        )}
      </p>
      {render_slot(@map)}
      <p>
        {t(@locale, "stats.public_month.peak_day", %{})} {if @peak,
          do: StatsFormat.peak_text(@locale, @page.stat.year, @page.stat.month, @peak, @page.unit),
          else: t(@locale, "common.not_available", %{})}
      </p>
      <p>
        {t(@locale, "stats.public_month.quietest_week", %{})} {StatsFormat.quietest_week(
          @locale,
          @page.stat.year,
          @page.stat.month,
          @page.stat.daily
        )}
      </p>
      <section :for={country <- @visited} class="min-w-0">
        <h2>{country["country"]}</h2>
        <p :for={city <- country["cities"]}>{city["city"]}</p>
      </section>
      <NativeChart.chart
        id="public-month-chart"
        public
        revision={"#{@page.stat.year}-#{@page.stat.month}"}
        label={t(@locale, "stats.public_month.distance_traveled", %{})}
        data={for [day, meters] <- @page.stat.daily, do: [day, StatsFormat.rounded(meters, "km")]}
      />
    </section>
    """
  end
end
