defmodule DawarichWeb.StatsLive.NativeParts do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.Analytics.Period
  alias DawarichWeb.{NativeChart, LocalizedDate, NumberFormat, StatsFormat}

  attr :data, :map, required: true
  attr :locale, :string, required: true
  attr :mode, :atom, required: true

  def page(assigns) do
    ~H"""
    <div class="min-w-0">
      <section
        :if={@data.restricted}
        id="stats-window-alert"
        role="alert"
        class="alert flex flex-wrap min-w-0"
      >
        <p class="break-words min-w-0">
          {t(
            @locale,
            "shared.plan_data_window_alert.your_lite_plan_includes_the_last_12_months_of_data",
            %{}
          )}
        </p>
        <button id="stats-upgrade" class="btn whitespace-normal" phx-click="upgrade">{t(
          @locale,
          "shared.plan_data_window_alert.upgrade_to_pro",
          %{}
        )}</button>
      </section>
      <%= if @mode == :index do %>
        <p id="stats-total">
          {NumberFormat.delimited(@locale, Period.rounded(@data.total_distance, @data.unit))} {@data.unit}
        </p>
        <p>
          {NumberFormat.delimited(@locale, @data.points.total)} {t(
            @locale,
            "stats.index.geopoints_tracked",
            %{}
          )}
        </p>
        <p
          :if={@data.points.state == :pending}
          id="stats-count-pending"
          role="status"
          aria-live="polite"
        >
          {t(@locale, "javascript.common.loading", %{})}
        </p>
        <div :if={@data.points.state == :ready} id="stats-count-ready">
          {NumberFormat.delimited(@locale, @data.points.geocoded)} / {NumberFormat.delimited(
            @locale,
            @data.points.total
          )} ({@data.points.percentage}%)
        </div>
        <p
          :if={@data.points.state == :ready && (@data.points.without_data || 0) > 0}
          id="stats-without-data"
        >
          {@data.points.without_data} {t(
            @locale,
            "stats.reverse_geocoding_stats.points_without_data",
            %{}
          )}
        </p>
        <div class="flex flex-wrap gap-2 min-w-0">
          <button
            class="btn btn-outline whitespace-normal"
            phx-click="open_places"
            phx-value-kind="countries"
          >{t(@locale, "stats.reverse_geocoding_stats.countries_visited", %{})}: {length(
            @data.countries_visited
          )}</button>
          <button
            class="btn btn-outline whitespace-normal"
            phx-click="open_places"
            phx-value-kind="cities"
          >{t(@locale, "stats.reverse_geocoding_stats.cities_visited", %{})}: {length(
            @data.cities_visited
          )}</button>
        </div>
        <article :for={year <- @data.years} class="my-4 min-w-0 rounded-lg border p-4">
          <.link navigate={"/stats/#{year.year}"} class="text-xl underline">{year.year}</.link>
          <p>{year.updated_on}</p>
          <p id={"stats-year-total-#{year.year}"}>
            {NumberFormat.delimited(@locale, Period.rounded(Enum.sum(year.distances), @data.unit))} {@data.unit}
          </p>
          <p id={"stats-year-places-#{year.year}"}>
            {length(countries(year.stats))} / {length(cities(year.stats))}
          </p>
          <NativeChart.chart
            id={"stats-year-#{year.year}"}
            data={months(@locale, year.year, year.distances, @data.unit)}
            revision={to_string(year.updated_on)}
            label={t(@locale, "stats.year.distance", %{})}
            options={%{suffix: " " <> @data.unit}}
          />
        </article>
        <p :for={year <- @data.locked_years} id={"stats-locked-#{year}"} class="my-4">
          {year} — {t(@locale, "stats.locked_year_card.available_on_pro", %{})}
        </p>
        <nav aria-label={t(@locale, "views.pagination.next", %{})} class="flex flex-wrap gap-2">
          <.link :if={@data.page > 1} patch={"/stats?page=#{@data.page-1}"} class="btn">{t(
            @locale,
            "views.pagination.previous",
            %{}
          )}</.link>
          <.link :if={@data.more} patch={"/stats?page=#{@data.page+1}"} class="btn">{t(
            @locale,
            "views.pagination.next",
            %{}
          )}</.link>
        </nav>
      <% else %>
        <p>{@data.year}<span :if={@mode == :month}> / {@data.month}</span></p>
        <%= if @mode == :year do %>
          <NativeChart.chart
            id="stats-native-chart"
            data={months(@locale, @data.year, @data.distances, @data.unit)}
            revision={to_string(@data.year)}
            label={t(@locale, "stats.year.distance", %{})}
            options={%{suffix: " " <> @data.unit}}
          />
          <article :for={stat <- @data.stats} class="my-4 border rounded-lg p-4 min-w-0">
            <.link href={"/stats/#{@data.year}/#{stat.month}"} class="underline">{LocalizedDate.month_name(
              @locale,
              @data.year,
              stat.month
            )}</.link>
            <p>
              {NumberFormat.delimited(@locale, Period.rounded(stat.distance, @data.unit))} {@data.unit}
            </p>
            <p id={"stats-month-places-#{stat.month}"} class="[overflow-wrap:anywhere]">
              {Enum.join(cities([stat]), ", ")}
            </p>
            <.link href={StatsFormat.year_map_path(@data.year)}>{t(@locale, "stats.year.map", %{})}</.link>
          </article>
        <% else %>
          <DawarichWeb.StatsLive.NativeMonthParts.summary data={@data} locale={@locale} />
          <%= if @data.data.stat do %>
            <NativeChart.chart
              id="stats-native-chart"
              data={
                Enum.map(@data.data.stat.daily, fn [day, meters] ->
                  [day, Period.rounded(meters, @data.unit)]
                end)
              }
              revision={"#{@data.year}-#{@data.month}"}
              label={t(@locale, "stats.year.distance", %{})}
              options={%{suffix: " " <> @data.unit}}
            />
            <.link :if={@data.peak} id="stats-peak-day" href={peak_path(@data)}>{StatsFormat.peak_text(
              @locale,
              @data.year,
              @data.month,
              @data.peak,
              @data.unit
            )}</.link>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :dialog, :any, required: true
  attr :data, :map, required: true
  attr :locale, :string, required: true

  def dialog(assigns) do
    ~H"""
    <section
      id="stats-dialog"
      role="dialog"
      aria-modal="true"
      aria-labelledby="stats-dialog-title"
      class="fixed inset-0 z-50 bg-base-100 p-6 overflow-y-auto min-w-0"
      phx-window-keydown="close_dialog"
      phx-key="Escape"
      phx-mounted={Phoenix.LiveView.JS.focus(to: "#stats-dialog-close")}
    >
      <h2 id="stats-dialog-title" class="text-xl break-words">
        {t(@locale, "stats.index.statistics", %{})}
      </h2>
      <button id="stats-dialog-close" class="btn" phx-click="close_dialog">{t(
        @locale,
        "stats.reverse_geocoding_stats.close",
        %{}
      )}</button>
      <ul :if={@dialog in ~w(countries cities)}>
        <li
          :for={
            value <-
              if(@dialog == "countries", do: @data.countries_visited, else: @data.cities_visited)
          }
          class="[overflow-wrap:anywhere]"
          phx-no-format
        >{value}</li>
      </ul>
      <nav
        :if={@dialog in ~w(countries cities)}
        aria-label={t(@locale, "stats.index.statistics", %{})}
        class="flex flex-wrap gap-2"
      >
        <.link :if={@data.places_page > 1} patch={places_path(@data, @dialog, -1)} class="btn">{t(
          @locale,
          "views.pagination.previous",
          %{}
        )}</.link>
        <.link :if={@data.places_more} patch={places_path(@data, @dialog, 1)} class="btn">{t(
          @locale,
          "views.pagination.next",
          %{}
        )}</.link>
      </nav>
      <form
        :if={@dialog == :share || is_map(@dialog)}
        id="stats-sharing"
        phx-submit="share"
        class="flex flex-wrap gap-3 min-w-0"
      >
        <input type="hidden" name="enabled" value="0" />
        <label for="stats-sharing-enabled">{t(
          @locale,
          "shared.sharing_modal.enable_public_access",
          %{}
        )}</label>
        <input type="checkbox" id="stats-sharing-enabled" name="enabled" value="1" checked={true} />
        <label for="stats-sharing-expiration">{t(@locale, "shared.sharing_modal.link_expiration", %{})}</label><select
          id="stats-sharing-expiration"
          name="expiration"
        ><option :for={value <- ~w(1h 12h 24h)} value={value}>{value}</option></select>
        <button class="btn btn-primary whitespace-normal" type="submit">{t(
          @locale,
          "helpers.submit.submit",
          %{}
        )}</button>
        <a
          :if={is_map(@dialog) && @dialog.url != ""}
          id="stats-sharing-url"
          href={@dialog.url}
          class="[overflow-wrap:anywhere]"
        >{@dialog.url}</a>
      </form>
    </section>
    """
  end

  defp countries(stats),
    do: stats |> Enum.flat_map(& &1.toponyms) |> Dawarich.Stats.Toponyms.countries()

  defp cities(stats),
    do: stats |> Enum.flat_map(& &1.toponyms) |> Dawarich.Stats.Toponyms.cities()

  defp places_path(data, kind, direction),
    do:
      "/stats?" <>
        URI.encode_query(%{
          "page" => data.page,
          "places_page" => data.places_page + direction,
          "places_kind" => kind
        })

  defp months(locale, year, distances, unit),
    do:
      for(
        {meters, month} <- Enum.with_index(distances, 1),
        do: [LocalizedDate.month_name(locale, year, month), Period.rounded(meters, unit)]
      )

  defp peak_path(data) do
    {first, last} = data.bounds
    "/map/v2?" <> URI.encode_query(%{"start_at" => first, "end_at" => last})
  end
end
