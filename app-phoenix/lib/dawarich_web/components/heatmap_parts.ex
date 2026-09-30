defmodule DawarichWeb.HeatmapParts do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1]

  alias Dawarich.Insights.Heatmap
  alias DawarichWeb.LocalizedDate

  attr :locale, :string, required: true
  attr :heatmap, :map, required: true
  attr :year, :integer, required: true
  attr :today, Date, required: true
  attr :unit, :string, required: true

  def heatmap(assigns) do
    weeks = Heatmap.weeks(assigns.year)

    assigns =
      assign(assigns,
        weeks: weeks,
        labels: margins(Heatmap.month_labels(weeks, assigns.year, assigns.locale))
      )

    ~H"""
    <div class="w-full lg:w-3/4 mb-6">
      <div
        id="activity-heatmap-card"
        phx-hook="RailsStimulus"
        phx-update="ignore"
        class="card bg-base-200"
        data-controller="activity-heatmap"
        data-activity-heatmap-unit-value={@unit}
        data-activity-heatmap-target-date-value={Heatmap.most_recent(@heatmap.daily) || ""}
      >
        <div class="card-body p-4">
          <div class="flex justify-between items-center mb-4">
            <div class="flex items-center gap-2">
              <.icon name="calendar" class="w-5 h-5 text-base-content/60" />
              <h3 class="text-lg font-semibold">
                {t(@locale, "insights.activity_heatmap.activity_overview", %{})}
              </h3>
            </div>
            <div class="badge badge-ghost">
              {@heatmap.active_days} {t(@locale, "insights.activity_heatmap.active_days", %{})}
            </div>
          </div>
          <div class="overflow-x-auto flex justify-center">
            <div class="min-w-fit relative">
              <div class="flex ml-8 mb-1">
                <div
                  :for={{margin, name} <- @labels}
                  style={"margin-left: #{margin}px"}
                  class="text-xs text-base-content/60"
                >
                  {name}
                </div>
              </div>
              <div class="flex">
                <div class="flex flex-col gap-0.5 mr-2 text-xs text-base-content/60">
                  <span :for={label <- day_labels(@locale)} class="h-3 flex items-center leading-none">{label}</span>
                </div>
                <div class="flex gap-0.5">
                  <div :for={week <- @weeks} class="flex flex-col gap-0.5">
                    <%= for cell <- cells(week, @heatmap, @year, @today) do %>
                      <div
                        :if={cell.active}
                        class={"w-3 h-3 rounded-sm cursor-pointer transition-opacity hover:opacity-80 #{cell.class}"}
                        data-date={cell.key}
                        data-distance={cell.distance}
                        data-action="mouseenter->activity-heatmap#showTooltip mouseleave->activity-heatmap#hideTooltip"
                      >
                      </div>
                      <div
                        :if={not cell.active}
                        class={"w-3 h-3 rounded-sm #{if cell.future, do: "bg-base-300/30", else: ""}"}
                      >
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
              <div class="flex items-center justify-end gap-2 mt-4 text-xs text-base-content/60">
                <span>{t(@locale, "insights.activity_heatmap.less", %{})}</span>
                <div class="flex gap-0.5">
                  <div class="w-3 h-3 rounded-sm bg-base-300"></div>
                  <div class="w-3 h-3 rounded-sm bg-success/30"></div>
                  <div class="w-3 h-3 rounded-sm bg-success/50"></div>
                  <div class="w-3 h-3 rounded-sm bg-success/70"></div>
                  <div class="w-3 h-3 rounded-sm bg-success"></div>
                </div>
                <span>{t(@locale, "insights.activity_heatmap.more", %{})}</span>
              </div>
            </div>
          </div>
          <div
            data-activity-heatmap-target="tooltip"
            class="hidden absolute z-50 flex-col items-center px-3 py-2 bg-base-100 border border-base-300 rounded-lg shadow-lg text-sm pointer-events-none"
          >
            <span data-activity-heatmap-target="tooltipDate" class="font-medium"></span>
            <span data-activity-heatmap-target="tooltipDistance" class="text-base-content/70"></span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp margins(labels) do
    {margins, _last} =
      Enum.map_reduce(labels, 0, fn %{index: index, name: name}, last ->
        {{(index - last) * 14, name}, index + 1}
      end)

    margins
  end

  defp day_labels(locale) do
    for key <- ["mon", nil, "wed", nil, "fri", nil, nil],
        do: key && t(locale, "insights.activity_heatmap." <> key, %{})
  end

  defp cells(week, heatmap, year, today) do
    for offset <- 0..6 do
      date = Date.add(week, offset)
      key = Date.to_iso8601(date)
      distance = Map.get(heatmap.daily, key, 0)
      in_year = date.year == year
      future = Date.compare(date, today) == :gt

      %{
        key: key,
        distance: distance,
        class: Heatmap.level_class(Heatmap.level(distance, heatmap.levels)),
        active: in_year and not future,
        future: in_year and future
      }
    end
  end

  attr :locale, :string, required: true
  attr :heatmap, :map, required: true
  attr :current_year, :boolean, required: true

  def streak(assigns) do
    ~H"""
    <div class="w-full lg:w-1/4 mb-6">
      <div class="card bg-base-200">
        <div class={"card-body p-3 #{unless @current_year, do: "justify-center"}"}>
          <div class="flex items-center gap-2 mb-2">
            <.icon name="flame" class="w-4 h-4 text-orange-500" />
            <h3 class="text-base font-semibold">
              {t(@locale, "insights.activity_streak.activity_streak", %{})}
            </h3>
          </div>
          <%= if @current_year do %>
            <div class="text-center mb-2">
              <div class="text-3xl font-bold text-primary">
                {@heatmap.current_streak}
                <span class="text-sm">{t(@locale, "insights.activity_streak.day", %{
                  count: @heatmap.current_streak
                })}</span>
              </div>
              <div class="text-xs text-base-content/60">
                {t(@locale, "insights.activity_streak.current", %{})}
              </div>
            </div>
            <div class="divider my-1"></div>
          <% end %>
          <div class="text-center">
            <div class="flex items-center justify-center gap-1 mb-1">
              <.icon name="trophy" class="w-3 h-3 text-warning" />
              <span class="text-xs font-medium text-base-content/70">{t(
                @locale,
                "insights.activity_streak.longest_streak",
                %{}
              )}</span>
            </div>
            <div class="text-xl font-bold">
              {@heatmap.longest_streak}
              {t(@locale, "insights.activity_streak.day", %{count: @heatmap.longest_streak})}
            </div>
            <div
              :if={@heatmap.longest_start && @heatmap.longest_end}
              class="text-xs text-base-content/40 mt-1"
            >
              {LocalizedDate.l(@locale, @heatmap.longest_start, "short_month_day_padded")} - {LocalizedDate.l(
                @locale,
                @heatmap.longest_end,
                "short_month_day_padded"
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
