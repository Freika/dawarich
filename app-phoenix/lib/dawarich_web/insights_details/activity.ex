defmodule DawarichWeb.InsightsDetails.Activity do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.Digests
  alias DawarichWeb.Icon
  alias DawarichWeb.InsightsDetails.Format

  @icons %{
    "driving" => "car",
    "walking" => "footprints",
    "stationary" => "user",
    "cycling" => "bike",
    "flying" => "plane",
    "train" => "train-front",
    "running" => "line-squiggle",
    "bus" => "bus",
    "boat" => "ship",
    "motorcycle" => "bike"
  }
  def render(assigns) do
    sorted =
      Map.get_lazy(assigns.data, :activity_pairs, fn ->
        Enum.sort_by(assigns.data.activity, fn {mode, _} -> {byte_size(mode), mode} end)
      end)
      |> Enum.reject(fn {mode, data} ->
        mode == "unknown" or Digests.to_i(data["duration"]) == 0
      end)
      |> Enum.sort_by(fn {_mode, data} -> -Digests.to_i(data["percentage"]) end)

    assigns = assign(assigns, sorted: sorted, icons: @icons)

    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-5">
        <h2 class="card-title text-lg flex items-center gap-2">
          <Icon.icon name="activity" class="w-5 h-5 text-primary" /> {tr(
            @locale,
            "activity_breakdown"
          )}
        </h2>
        <div class="space-y-3 mt-3">
          <%= if @sorted == [] do %>
            <div class="text-sm text-base-content/60 text-center py-4">
              {tr(@locale, "no_activity_data_available_for_this_period")}
            </div>
          <% else %>
            <div :for={{mode, data} <- @sorted} class="flex items-center gap-3">
              <div class="w-6 flex justify-center text-base-content/70">
                <Icon.icon name={@icons[mode] || "circle"} class="w-4 h-4" />
              </div>
              <span class="w-20 text-sm">{label(@locale, mode)}</span>
              <progress class="progress progress-info flex-1 h-2" value={data["percentage"]} max="100"></progress>
              <span class="w-16 text-right text-sm text-base-content/60">{Format.duration(
                @locale,
                data["duration"]
              )}</span>
              <span class="w-10 text-right text-sm font-medium">{data["percentage"]}%</span>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp tr(locale, key), do: Format.translation(locale, "activity_breakdown", key)

  defp label(locale, mode) do
    if Map.has_key?(@icons, mode),
      do: tr(locale, mode),
      else: t(locale, "transportation_modes." <> mode, %{})
  end
end
