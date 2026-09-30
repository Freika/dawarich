defmodule DawarichWeb.InsightsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.HeatmapParts
  import DawarichWeb.InsightsParts
  import DawarichWeb.StatsCards, only: [plan_alert: 1]

  alias Dawarich.{Insights, Stats}
  alias DawarichWeb.{Params, StatsFormat}

  @locked_cards ~w(insights_total_distance insights_countries insights_cities insights_days_traveling activity_heatmap activity_streak year_comparison activity_breakdown location_clusters monthly_digest travel_patterns movement_wellness)

  @impl true
  def mount(params, _session, socket),
    do: {:ok, assign(socket, page(socket.assigns.current_user, params, socket.assigns))}

  def page(user, params, %{locale: locale, now: now, self_hosted: self_hosted}) do
    context = Stats.context(user, now, self_hosted)
    data = Insights.page(user, params, context)

    Map.merge(data, %{
      page_title: t(locale, "insights.index.insights", %{}),
      rails_js: true,
      today: context.today,
      unit: StatsFormat.unit(user.settings),
      label:
        if(data.all_time,
          do: t(locale, "controllers.insights.all_time", %{}),
          else: t(locale, "controllers.insights.year_overview", %{year: data.year})
        ),
      details_src:
        "/insights/details?" <>
          Params.to_query(
            for(
              {k, v} <- %{"year" => data.selected, "month" => params["month"]},
              v != nil,
              into: %{},
              do: {k, v}
            )
          )
    })
  end

  @impl true
  def render(assigns) do
    upgrade =
      &StatsFormat.upgrade_url(assigns.current_user, assigns.now, assigns.self_hosted, &1, &2)

    assigns =
      assign(assigns,
        alert_href: assigns.restricted && upgrade.("data_window", "insights"),
        badge: assigns.year_locked && upgrade.("badge", "pro_badge"),
        upgrades:
          if(assigns.year_locked,
            do: Map.new(@locked_cards, &{&1, upgrade.("insights", &1)}),
            else: %{}
          )
      )

    ~H"""
    <div class="w-full my-5">
      <.header
        locale={@locale}
        available={@available}
        locked={@locked}
        all_time={@all_time}
        year={@year}
        label={@label}
      />
      <.plan_alert :if={@restricted} locale={@locale} href={@alert_href} />

      <%= if @year_locked do %>
        <div class="grid grid-cols-1 sm:grid-cols-4 gap-4 mb-6">
          <.locked_card
            :for={metric <- ~w(total_distance countries cities days_traveling)}
            locale={@locale}
            title={t(@locale, "insights.index.#{metric}", %{})}
            href={@upgrades["insights_" <> metric]}
            badge={@badge}
          />
        </div>
        <div class="flex flex-col lg:flex-row gap-6">
          <div class="w-full lg:w-3/4 mb-6">
            <.locked_card
              locale={@locale}
              title={t(@locale, "insights.index.activity_heatmap", %{})}
              href={@upgrades["activity_heatmap"]}
              badge={@badge}
            />
          </div>
          <div class="w-full lg:w-1/4 mb-6">
            <.locked_card
              locale={@locale}
              title={t(@locale, "insights.index.activity_streak", %{})}
              href={@upgrades["activity_streak"]}
              badge={@badge}
            />
          </div>
        </div>
        <turbo-frame id="insights_details">
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6 mt-6">
            <div class="space-y-6">
              <.locked_card
                :for={card <- ~w(year_comparison activity_breakdown location_clusters)}
                locale={@locale}
                title={t(@locale, "insights.index.#{card}", %{})}
                href={@upgrades[card]}
                badge={@badge}
              />
            </div>
            <div class="space-y-6">
              <.locked_card
                :for={card <- ~w(monthly_digest travel_patterns)}
                locale={@locale}
                title={t(@locale, "insights.index.#{card}", %{})}
                href={@upgrades[card]}
                badge={@badge}
              />
            </div>
          </div>
          <.locked_card
            locale={@locale}
            title={t(@locale, "insights.index.movement_wellness", %{})}
            href={@upgrades["movement_wellness"]}
            badge={@badge}
          />
        </turbo-frame>
      <% else %>
        <.stats_row locale={@locale} totals={@totals} all_time={@all_time} year={@year} unit={@unit} />

        <div class="flex flex-col lg:flex-row gap-6">
          <.heatmap
            :if={not @all_time}
            locale={@locale}
            heatmap={@heatmap}
            year={@year}
            today={@today}
            unit={@unit}
          />
          <.streak
            :if={not @all_time}
            locale={@locale}
            heatmap={@heatmap}
            current_year={@year == @today.year}
          />
        </div>

        <turbo-frame
          :if={not @restricted and not @all_time}
          loading="lazy"
          id="residency-content"
          src={"/map/residency?year=#{@year}"}
          phx-update="ignore"
        >
          <.days_per_country_skeleton />
        </turbo-frame>

        <turbo-frame loading="lazy" id="insights_details" src={@details_src} phx-update="ignore">
          <.details_skeleton />
        </turbo-frame>
      <% end %>

      <div class="text-center text-sm text-base-content/50 py-4">
        {t(@locale, "insights.index.geodata_insights_bull_powered_by_your_location_history", %{})}
      </div>
    </div>
    """
  end
end
