defmodule DawarichWeb.StatsCards do
  @moduledoc false
  use DawarichWeb, :html

  alias DawarichWeb.{Icon, NumberFormat}
  alias Phoenix.LiveView.JS

  attr :locale, :string, required: true
  attr :href, :string, required: true

  def plan_alert(assigns) do
    ~H"""
    <div
      data-controller="removals"
      data-removals-timeout-value="0"
      role="alert"
      class="alert alert-info shadow-lg my-4 !flex !flex-row !items-center justify-between gap-4"
    >
      <div class="flex items-center gap-2 min-w-0">
        <Icon.icon name="info" class="flex-shrink-0" />
        <span>{t(
          @locale,
          "shared.plan_data_window_alert.your_lite_plan_includes_the_last_12_months_of_data",
          %{}
        )}</span>
      </div>
      <div class="flex items-center gap-2 flex-shrink-0">
        <a href={@href} class="btn btn-sm btn-primary" target="_blank" rel="noopener">{t(
          @locale,
          "shared.plan_data_window_alert.upgrade_to_pro",
          %{}
        )}</a>
        <button
          type="button"
          data-action="click->removals#remove"
          phx-click={JS.hide(to: {:closest, "[role='alert']"}, transition: "fade-out", time: 150)}
          class="btn btn-sm btn-circle btn-ghost"
          aria-label={t(@locale, "shared.plan_data_window_alert.close", %{})}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-5 w-5"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          ><path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M6 18L18 6M6 6l12 12"
          /></svg>
        </button>
      </div>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :points, :map, required: true
  attr :store_geodata, :boolean, required: true
  attr :countries, :list, required: true
  attr :cities, :list, required: true

  def reverse_geocoding(assigns) do
    ~H"""
    <div :if={@store_geodata} class="stat text-center">
      <div class="stat-value text-secondary">{NumberFormat.delimited(@locale, @points.geocoded)}</div>
      <div class="stat-title">
        {t(@locale, "stats.reverse_geocoding_stats.reverse_geocoded_points", %{})}
      </div>
      <div class="stat-desc">
        {t(@locale, "stats.reverse_geocoding_stats.percent_of_total", %{
          percent: NumberFormat.precision_one(@locale, @points.percentage)
        })}
      </div>
      <div :if={(@points.without_data || 0) > 0} class="stat-title">
        <span
          class="tooltip underline decoration-dotted"
          data-tip={
            t(
              @locale,
              "stats.reverse_geocoding_stats.points_that_were_reverse_geocoded_but_had_no_data",
              %{}
            )
          }
        >{NumberFormat.delimited(@locale, @points.without_data)} {t(
          @locale,
          "stats.reverse_geocoding_stats.points_without_data",
          %{}
        )}</span>
      </div>
    </div>
    <div class="stat text-center">
      <div
        class="stat-value text-warning underline hover:no-underline hover:cursor-pointer"
        onclick="countries_visited.showModal()"
      >
        {NumberFormat.delimited(@locale, length(@countries))}
      </div>
      <div class="stat-title">
        {t(@locale, "stats.reverse_geocoding_stats.countries_visited", %{})}
      </div>
      <dialog id="countries_visited" class="modal" phx-update="ignore">
        <div class="modal-box">
          <h3 class="font-bold text-lg">
            {t(@locale, "stats.reverse_geocoding_stats.countries_visited", %{})}
          </h3>
          <p class="py-4" phx-no-format><p :for={country <- @countries}>{country}</p></p>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button>{t(@locale, "stats.reverse_geocoding_stats.close", %{})}</button>
        </form>
      </dialog>
    </div>
    <div class="stat text-center">
      <div
        class="stat-value hover:cursor-pointer hover:no-underline underline"
        onclick="cities_visited.showModal()"
      >
        {length(@cities)}
      </div>
      <div class="stat-title">{t(@locale, "stats.reverse_geocoding_stats.cities_visited", %{})}</div>
      <dialog id="cities_visited" class="modal" phx-update="ignore">
        <div class="modal-box">
          <h3 class="font-bold text-lg">
            {t(@locale, "stats.reverse_geocoding_stats.cities_visited", %{})}
          </h3>
          <p class="py-4" phx-no-format><p :for={city <- @cities}>{city}</p></p>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button>{t(@locale, "stats.reverse_geocoding_stats.close", %{})}</button>
        </form>
      </dialog>
    </div>
    """
  end
end
