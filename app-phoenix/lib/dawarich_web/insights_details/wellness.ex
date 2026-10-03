defmodule DawarichWeb.InsightsDetails.Wellness do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.Digests
  alias DawarichWeb.Icon
  alias DawarichWeb.InsightsDetails.Format

  def render(assigns) do
    stats = statistics(assigns.data.activity)

    assigns =
      assign(assigns,
        stats: stats,
        present:
          Enum.sum(
            Enum.map(assigns.data.activity, fn {_mode, data} -> Digests.to_i(data["duration"]) end)
          ) > 0,
        modes: [
          {"walking", "footprints"},
          {"running", "footprints"},
          {"cycling", "bike"},
          {"driving", "car"}
        ]
      )

    ~H"""
    <div class="card bg-base-200 mb-6">
      <div class="card-body p-5">
        <h2 class="card-title text-lg flex items-center gap-2 mb-4">
          <Icon.icon name="heart" class="w-5 h-5 text-error" /> {tr(@locale, "movement_wellness")}
        </h2>
        <%= if @present do %>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div class="space-y-4">
              <div>
                <div class="text-sm font-medium mb-2">{tr(@locale, "active_time")}</div><div class="space-y-2">
                  <div
                    :for={{mode, icon} <- @modes}
                    :if={@stats[mode] > 0}
                    class="flex items-center justify-between text-sm"
                  >
                    <div class="flex items-center gap-2">
                      <Icon.icon name={icon} class="w-4 h-4 text-base-content/70" /><span>{tr(
                        @locale,
                        mode
                      )}</span>
                    </div><span class="font-medium">{Format.activity_hours(@locale, @stats[mode])} {tr(
                      @locale,
                      "total"
                    )}</span>
                  </div>
                  <div
                    :if={Enum.all?(@modes, fn {mode, _} -> @stats[mode] == 0 end)}
                    class="text-sm text-base-content/60"
                  >
                    {tr(@locale, "no_activity_data_available_for_this_period")}
                  </div>
                </div>
              </div>
            </div>
            <div class="space-y-4">
              <div>
                <div class="text-sm font-medium mb-2">{tr(@locale, "sedentary_vs_active")}</div><div class="space-y-1 text-sm">
                  <div :if={@stats["transport"] > 0} class="flex justify-between">
                    <span>{tr(@locale, "in_transport")}</span><span>{Format.activity_hours(
                      @locale,
                      @stats["transport"]
                    )}</span>
                  </div>
                  <div :if={@stats["stationary"] > 0} class="flex justify-between">
                    <span>{tr(@locale, "stationary")}</span><span>{Format.activity_hours(
                      @locale,
                      @stats["stationary"]
                    )}</span>
                  </div>
                  <div :if={@stats["active"] > 0} class="flex justify-between text-success">
                    <span>{tr(@locale, "active_movement")}</span><span>{Format.activity_hours(
                      @locale,
                      @stats["active"]
                    )}</span>
                  </div>
                  <div
                    :if={@stats["active"] > 0 and @stats["stationary"] + @stats["transport"] > 0}
                    class="flex justify-between pt-1 border-t border-base-300 text-base-content/60"
                  >
                    <span>{tr(@locale, "ratio")} 1:{round(
                      (@stats["stationary"] + @stats["transport"]) / @stats["active"]
                    )} {tr(@locale, "active_vs_sedentary")}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% else %>
          <div class="text-center py-8 text-base-content/60">
            <div class="flex flex-col items-center gap-2">
              <Icon.icon name="heart" class="w-8 h-8 opacity-50" /><p>
                {tr(@locale, "no_movement_data_available_for_this_period")}
              </p><p class="text-sm">
                {tr(@locale, "track_data_with_transportation_modes_will_appear_here")}
              </p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp tr(locale, key), do: Format.translation(locale, "movement_wellness", key)

  defp statistics(activity) do
    start = Map.new(~w(walking cycling running driving transport active stationary), &{&1, 0})

    Enum.reduce(activity, start, fn {mode, data}, stats ->
      n = Digests.to_i(data["duration"])

      cond do
        mode in ~w(walking running cycling) ->
          stats |> Map.put(mode, n) |> Map.update!("active", &(&1 + n))

        mode == "stationary" ->
          Map.put(stats, "stationary", n)

        mode in ~w(driving bus train flying boat motorcycle) ->
          stats = if mode == "driving", do: Map.put(stats, "driving", n), else: stats
          Map.update!(stats, "transport", &(&1 + n))

        true ->
          stats
      end
    end)
  end
end
