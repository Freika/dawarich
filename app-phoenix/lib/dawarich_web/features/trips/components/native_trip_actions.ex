defmodule DawarichWeb.NativeTripActions do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{Icon, HumanDatetime}
  attr :page, :map, required: true
  attr :locale, :string, required: true

  def actions(assigns) do
    ~H"""
    <div id="native-trip-header" class="mb-6">
      <div class="flex flex-wrap items-start justify-between gap-3 mb-1">
        <h1 class="text-3xl font-bold leading-tight min-w-0 [overflow-wrap:anywhere]">
          {@page.name}
        </h1>
        <div class="flex flex-wrap items-center gap-1 shrink-0" data-testid="trip-header-actions">
          <a
            href={"/map/v2?" <> DawarichWeb.Params.to_query(%{"start_at" => HumanDatetime.iso8601(@page.started_at), "end_at" => HumanDatetime.iso8601(@page.ended_at)})}
            data-testid="trip-open-map"
            class="btn btn-sm btn-ghost"
            title={s(@locale, "open_in_map")}
            aria-label={s(@locale, "open_in_map")}
          ><Icon.icon name="map" class="w-4 h-4" /></a>
          <div class="dropdown dropdown-end">
            <label tabindex="0" class="btn btn-sm btn-ghost" title={s(@locale, "download_trip")}><Icon.icon
              name="download"
              class="w-4 h-4"
            /></label>
            <ul
              tabindex="0"
              class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-44 z-10"
            >
              <li :for={{format, key} <- [{"gpx", "gpx"}, {"json", "geojson"}]}>
                <a href="#" phx-click="trip:export" phx-value-format={format}>{s(@locale, key)}</a>
              </li>
            </ul>
          </div>
          <button
            :for={{kind, icon} <- [{"poster", "image"}, {"video", "video"}]}
            type="button"
            class="btn btn-sm btn-ghost"
            data-testid={"map-button-#{kind}"}
            aria-label={s(@locale, "create_" <> kind)}
            title={
              s(@locale, if(@page.has_path, do: "create_" <> kind, else: kind <> "_unavailable"))
            }
            disabled={!@page.has_path}
          ><Icon.icon name={icon} class="w-4 h-4" /></button>
          <a
            href={"/trips/#{@page.id}/edit"}
            class="btn btn-sm btn-ghost"
            title={s(@locale, "edit_trip")}
          ><Icon.icon name="square-pen" class="w-4 h-4" /></a>
          <a
            href={"/trips/#{@page.id}/share_link/new"}
            class="btn btn-sm btn-ghost relative"
            title={s(@locale, "share_trip")}
          ><Icon.icon name="share" class="w-4 h-4" /><span
            :if={@page.shared}
            class="badge badge-success badge-xs"
            aria-label={s(@locale, "currently_shared")}
          >{s(@locale, "public")}</span></a>
          <form class="button_to" method="post" action={"/trips/#{@page.id}"} phx-submit="trip:delete">
            <input type="hidden" name="_method" value="delete" />
            <button
              type="submit"
              class="btn btn-sm btn-ghost text-error"
              title={s(@locale, "delete_trip")}
              data-confirm={s(@locale, "delete_this_trip_this_cannot_be_undone")}
            ><Icon.icon name="trash-2" class="w-4 h-4" /></button>
            <input type="hidden" name="authenticity_token" value="" />
          </form>
        </div>
      </div>
      <p class="text-md text-base-content/60 mb-4">
        {DawarichWeb.MapParts.human_date(@locale, NaiveDateTime.to_date(@page.started_at.local))} {s(
          @locale,
          "ndash"
        )} {DawarichWeb.MapParts.human_date(@locale, NaiveDateTime.to_date(@page.ended_at.local))}
      </p>
      <DawarichWeb.TripParts.countries page={@page} locale={@locale} />
    </div>
    """
  end

  defp s(locale, key), do: t(locale, "trips.show." <> key, %{})
end
