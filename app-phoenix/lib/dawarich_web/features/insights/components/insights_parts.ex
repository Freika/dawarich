defmodule DawarichWeb.InsightsParts do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1]

  alias DawarichWeb.NumberFormat

  attr :locale, :string, required: true
  attr :available, :list, required: true
  attr :locked, :list, required: true
  attr :all_time, :boolean, required: true
  attr :year, :integer, default: nil
  attr :label, :string, required: true

  def header(assigns) do
    ~H"""
    <div class="mb-6">
      <div class="flex items-center gap-2 mb-1">
        <.icon name="compass" class="w-7 h-7 text-primary" />
        <h1 class="text-3xl font-bold">{t(@locale, "insights.header.insights", %{})}</h1>
        <p class="text-base-content/60 hidden sm:inline">
          {t(@locale, "insights.header.your_personal_movement_analytics_and_travel_patterns", %{})}
        </p>
      </div>
      <div class="flex gap-2 mt-2">
        <div :if={@available != []} class="dropdown">
          <label tabindex="0" class="btn btn-sm btn-outline">
            {@label}
            <.icon name="chevron-down" class="w-4 h-4 ml-1" />
          </label>
          <ul tabindex="0" class="dropdown-content z-[1] menu p-2 shadow bg-base-200 rounded-box w-52">
            <li>
              <a class={if @all_time, do: "active", else: ""} href="/insights?year=all">{t(
                @locale,
                "insights.header.all_time",
                %{}
              )}</a>
            </li>
            <li class="menu-title">
              <span class="p-2">{t(@locale, "insights.header.by_year", %{})}</span>
            </li>
            <li :for={year <- @available}>
              <a
                class={if not @all_time and year == @year, do: "active", else: ""}
                href={"/insights?year=#{year}"}
              >
                {year} {t(@locale, "insights.header.overview", %{})}
                <.icon :if={year in @locked} name="lock" class="w-3 h-3 inline opacity-50" />
              </a>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :totals, :map, required: true
  attr :all_time, :boolean, required: true
  attr :year, :integer, default: nil
  attr :unit, :string, required: true

  def stats_row(%{totals: %{any: false}} = assigns) do
    ~H"""
    <div class="alert alert-info mb-6">
      <.icon name="info" class="w-5 h-5" />
      <span>{t(@locale, "insights.stats_row.no_stats_data_available", %{})}{if @all_time,
        do: "",
        else: " for #{@year}"}{t(
        @locale,
        "insights.stats_row.stats_are_calculated_from_your_tracked_points",
        %{}
      )}</span>
    </div>
    """
  end

  def stats_row(assigns) do
    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-4 gap-4 mb-6">
      <.metric
        icon="chart-bar"
        label={t(@locale, "insights.stats_row.total_distance", %{})}
        value={"#{NumberFormat.delimited(@locale, @totals.distance)} #{@unit}"}
        note={note(@locale, @all_time, "this_year")}
      />
      <.metric
        icon="globe"
        label={t(@locale, "insights.stats_row.countries", %{})}
        value={@totals.countries}
        note={note(@locale, @all_time, "this_year")}
      />
      <.metric
        icon="building"
        label={t(@locale, "insights.stats_row.cities", %{})}
        value={@totals.cities}
        note={note(@locale, @all_time, "this_year")}
      />
      <.metric
        icon="calendar"
        label={t(@locale, "insights.stats_row.days_traveling", %{})}
        value={@totals.days}
        note={note(@locale, @all_time, "active_days_this_year")}
      />
    </div>
    """
  end

  defp note(locale, true, _key), do: t(locale, "insights.stats_row.all_tracked_history", %{})
  defp note(locale, false, key), do: t(locale, "insights.stats_row." <> key, %{})

  defp metric(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4">
        <div class="flex justify-between items-start">
          <div class="flex items-center gap-2 text-base-content/60 text-sm">
            <.icon name={@icon} class="w-4 h-4" />
            {@label}
          </div>
        </div>
        <div class="text-3xl font-bold mt-2">{@value}</div>
        <div class="text-base-content/50 text-sm">
          {@note}
        </div>
      </div>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :title, :string, required: true
  attr :href, :string, required: true
  attr :badge, :string, required: true

  def locked_card(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-xl">
      <div class="card-body p-5">
        <h2 class="card-title text-base-content/80">
          {@title}
          <a
            href={@badge}
            target="_blank"
            rel="noopener noreferrer"
            class="tooltip tooltip-bottom"
            data-tip={t(@locale, "helpers.application.pro_only", %{})}
            tabindex="0"
          ><span class="badge badge-sm badge-outline gap-1"><.icon name="lock" class="w-3 h-3" />{t(
            @locale,
            "helpers.application.pro_badge",
            %{}
          )}</span></a>
        </h2>
        <div class="relative mt-2">
          <div
            class="opacity-15 blur-[3px] pointer-events-none select-none space-y-3"
            aria-hidden="true"
          >
            <div class="h-3 bg-base-content/20 rounded w-3/4"></div>
            <div class="h-3 bg-base-content/20 rounded w-1/2"></div>
            <div class="h-3 bg-base-content/20 rounded w-5/6"></div>
            <div class="h-3 bg-base-content/20 rounded w-2/3"></div>
          </div>
          <div class="absolute inset-0 flex flex-col items-center justify-center">
            <.icon name="lock" class="w-6 h-6 opacity-30" />
            <p class="text-sm text-base-content/50 mt-1">
              {t(@locale, "insights.pro_locked_card.available_on_pro", %{})}
            </p>
            <a href={@href} class="btn btn-sm btn-primary mt-2" target="_blank" rel="noopener">
              {t(@locale, "insights.pro_locked_card.upgrade_to_pro", %{})}
            </a>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :lines, :integer, default: 3
  attr :chart_height, :string, default: nil

  def skeleton_card(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-5 space-y-4">
        <div class="h-6 w-48 bg-base-300 rounded animate-pulse"></div>
        <div :if={@chart_height} class={"#{@chart_height} w-full bg-base-300 rounded animate-pulse"}>
        </div>
        <div class="space-y-2">
          <div
            :for={i <- 0..(@lines - 1)}
            class={"h-4 #{Enum.at(~w(w-full w-3/4 w-5/6 w-2/3 w-4/5), rem(i, 5))} bg-base-300 rounded animate-pulse"}
          >
          </div>
        </div>
      </div>
    </div>
    """
  end

  def details_skeleton(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
      <div class="space-y-6">
        <.skeleton_card :for={_ <- 1..3} lines={3} />
      </div>
      <div class="space-y-6">
        <.skeleton_card :for={_ <- 1..2} lines={2} chart_height="h-40" />
      </div>
    </div>
    <div class="card bg-base-200 mb-6">
      <div class="card-body p-5 space-y-4">
        <div class="h-6 w-56 bg-base-300 rounded animate-pulse"></div>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div :for={_ <- 1..3} class="h-24 bg-base-300 rounded animate-pulse"></div>
        </div>
      </div>
    </div>
    """
  end

  def days_per_country_skeleton(assigns) do
    ~H"""
    <div class="flex flex-col lg:flex-row gap-6">
      <div class="w-full lg:w-1/4 mb-6">
        <.skeleton_card lines={3} />
      </div>
      <div class="w-full lg:w-3/4 mb-6">
        <.skeleton_card lines={4} />
      </div>
    </div>
    """
  end
end
