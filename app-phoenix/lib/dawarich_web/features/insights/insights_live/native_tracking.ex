defmodule DawarichWeb.InsightsLive.NativeTracking do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.NumberFormat
  attr :data, :map, required: true
  attr :locale, :string, required: true

  def render(assigns) do
    assigns = assign(assigns, :index, assigns.data.index)

    ~H"""
    <div
      class="flex flex-wrap items-center gap-x-5 gap-y-2 mb-6 text-sm text-base-content/70"
      id="native-insights-tracking"
    >
      <span><strong class="text-base-content tabular-nums">{NumberFormat.delimited(
        @locale,
        @index.points.total
      )}</strong> {t(@locale, "stats.index.geopoints_tracked", %{})}</span>
      <%= if @data.geocoding do %>
        <span :if={@data.store_geodata && @index.points.state == :ready} id="stats-count-ready">
          <strong class="text-base-content tabular-nums">{NumberFormat.delimited(
            @locale,
            @index.points.geocoded
          )}</strong>
          {t(@locale, "stats.reverse_geocoding_stats.reverse_geocoded_points", %{})} ({t(
            @locale,
            "stats.reverse_geocoding_stats.percent_of_total",
            %{percent: percentage(@index.points.percentage)}
          )})
        </span>
        <span
          :if={
            @data.store_geodata && @index.points.state == :ready &&
              (@index.points.without_data || 0) > 0
          }
          class="tooltip underline decoration-dotted"
          data-tip={
            t(
              @locale,
              "stats.reverse_geocoding_stats.points_that_were_reverse_geocoded_but_had_no_data",
              %{}
            )
          }
        >
          {NumberFormat.delimited(@locale, @index.points.without_data)} {t(
            @locale,
            "stats.reverse_geocoding_stats.points_without_data",
            %{}
          )}
        </span>
        <button
          :for={
            {kind, count} <- [{"countries", @index.total_countries}, {"cities", @index.total_cities}]
          }
          type="button"
          class="link link-hover"
          phx-click="open_places"
          phx-value-kind={kind}
        >
          <strong class="text-base-content tabular-nums">{NumberFormat.delimited(@locale, count)}</strong> {t(
            @locale,
            "stats.reverse_geocoding_stats.#{kind}_visited",
            %{}
          )}
        </button>
        <dialog
          :for={
            {kind, names} <- [
              {"countries", @index.countries_visited},
              {"cities", @index.cities_visited}
            ]
          }
          id={kind <> "_visited"}
          class="modal"
        >
          <div class="modal-box">
            <h3 class="font-bold text-lg mb-3">
              {t(@locale, "stats.reverse_geocoding_stats.#{kind}_visited", %{})}
            </h3>
            <ul class="space-y-1">
              <li :for={name <- names}>{name}</li>
            </ul>
          </div>
          <form method="dialog" class="modal-backdrop">
            <button>{t(@locale, "stats.reverse_geocoding_stats.close", %{})}</button>
          </form>
        </dialog>
      <% end %>
      <span class="text-xs text-base-content/50 basis-full">{t(
        @locale,
        "stats.index.all_stats_data_above_except_for_total_distance_and_number",
        %{}
      )}</span>
    </div>
    <p :if={@index.points.state == :pending} id="stats-count-pending" role="status" class="sr-only">
      {t(@locale, "javascript.common.loading", %{})}
    </p>
    """
  end

  defp percentage(value),
    do: :erlang.float_to_binary(value * 1.0, decimals: 1) |> String.trim_trailing(".0")
end
