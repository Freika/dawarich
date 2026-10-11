defmodule DawarichWeb.NativeTripActions do
  @moduledoc false
  use DawarichWeb, :html
  attr :page, :map, required: true
  attr :locale, :string, required: true

  def actions(assigns) do
    ~H"""
    <div data-testid="trip-header-actions" class="flex flex-wrap min-w-0 gap-2 mb-4">
      <a
        href={"/map/v2?" <> DawarichWeb.Params.to_query(%{"start_at" => DawarichWeb.HumanDatetime.iso8601(@page.started_at), "end_at" => DawarichWeb.HumanDatetime.iso8601(@page.ended_at)})}
        data-testid="trip-open-map"
        class="btn btn-sm btn-ghost h-auto whitespace-normal"
      >{t(@locale, "trips.show.open_in_map", %{})}</a>
      <button
        :for={{format, key} <- [{"gpx", "gpx"}, {"json", "geojson"}]}
        type="button"
        phx-click="trip:export"
        phx-value-format={format}
        class="btn btn-sm btn-ghost h-auto whitespace-normal"
      >{t(@locale, "trips.show.#{key}", %{})}</button>
      <a href={"/trips/#{@page.id}/edit"} class="btn btn-sm btn-ghost h-auto whitespace-normal">{t(
        @locale,
        "trips.show.edit_trip",
        %{}
      )}</a>
      <a
        href={"/trips/#{@page.id}/share_link/new"}
        class="btn btn-sm btn-ghost h-auto whitespace-normal"
      >{t(@locale, "trips.show.share_trip", %{})}<span
        :if={@page.shared}
        class="badge badge-success badge-xs"
      >{t(@locale, "trips.show.public", %{})}</span></a>
      <button
        type="button"
        phx-click="trip:recalculate"
        disabled={@page.recalculating}
        data-confirm={
          t(
            @locale,
            "trips.recalculate_button.recalculate_this_trip_s_path_distance_and_countries_from_your",
            %{}
          )
        }
        class="btn btn-sm btn-outline h-auto whitespace-normal"
      >{t(
        @locale,
        if(@page.recalculating,
          do: "trips.recalculate_button.recalculating_hellip",
          else: "trips.recalculate_button.recalculate"
        ),
        %{}
      )}</button>
      <button
        type="button"
        phx-click="trip:delete"
        data-confirm={t(@locale, "trips.show.delete_this_trip_this_cannot_be_undone", %{})}
        class="btn btn-sm btn-ghost text-error h-auto whitespace-normal"
      >{t(@locale, "trips.show.delete_trip", %{})}</button>
    </div>
    """
  end
end
