defmodule DawarichWeb.InsightsDetails.Body do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{InsightsParts, StatsFormat}

  def render(assigns) do
    assigns =
      if assigns.data.restricted do
        assign(assigns,
          badge:
            StatsFormat.upgrade_url(
              assigns.current_user,
              assigns.now,
              assigns.self_hosted,
              "badge",
              "pro_badge"
            ),
          upgrades:
            Map.new(
              ~w(year_comparison activity_breakdown location_clusters monthly_digest travel_patterns movement_wellness),
              &{&1,
               StatsFormat.upgrade_url(
                 assigns.current_user,
                 assigns.now,
                 assigns.self_hosted,
                 "insights",
                 &1
               )}
            )
        )
      else
        assigns
      end

    ~H"""
    <turbo-frame id="insights_details">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <div class="space-y-6">
          <.card
            :for={name <- ~w(year_comparison activity_breakdown location_clusters)}
            name={name}
            data={@data}
            locale={@locale}
            parent={assigns}
          />
        </div>
        <div class="space-y-6">
          <.card
            :for={name <- ~w(monthly_digest travel_patterns)}
            name={name}
            data={@data}
            locale={@locale}
            parent={assigns}
          />
        </div>
      </div>
      <.card name="movement_wellness" data={@data} locale={@locale} parent={assigns} />
    </turbo-frame>
    """
  end

  defp card(assigns) do
    ~H"""
    <%= if @data.restricted do %>
      <InsightsParts.locked_card
        locale={@locale}
        title={t(@locale, "insights.details." <> @name, %{})}
        badge={@parent.badge}
        href={@parent.upgrades[@name]}
      />
    <% else %>
      {Phoenix.HTML.raw(@parent.fragments[@name])}
    <% end %>
    """
  end
end
