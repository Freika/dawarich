defmodule DawarichWeb.PointListTable do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.HumanDatetime, only: [human_datetime_with_seconds: 1]
  import DawarichWeb.Icon, only: [icon: 1]
  alias DawarichWeb.{PointListControls, PointListFormat}

  attr :locale, :string, required: true
  attr :rows, :list, required: true
  attr :query, :map, required: true
  attr :geocoding, :boolean, required: true
  attr :unit, :string, required: true
  attr :selected, :any, required: true
  attr :csrf, :string, default: ""

  def table(assigns) do
    ~H"""
    <div id="points">
      <form
        id="bulk_destroy_form"
        action={PointListControls.bulk_action(@query)}
        accept-charset="UTF-8"
        method="post"
        phx-submit="confirm_delete"
      >
        <input type="hidden" name="_method" value="delete" />
        <input type="hidden" name="authenticity_token" value={@csrf} />
        <input
          type="submit"
          name="commit"
          value={t(@locale, "points.index.delete_selected", %{})}
          class="btn btn-error btn-sm mb-3"
          style={if MapSet.size(@selected) == 0, do: "display: none;"}
          phx-click="confirm_delete"
        />
        <div class="border border-base-300 rounded-xl overflow-x-auto">
          <table class="table table-sm w-full">
            <thead class="bg-base-200">
              <tr>
                <th class="px-3 py-2.5 w-1/12">
                  <input
                    type="checkbox"
                    name="select_all"
                    id="select_all_points"
                    value="1"
                    aria-label={t(@locale, "points.index.select_all", %{})}
                    phx-click="select_all"
                    checked={@rows != [] and MapSet.size(@selected) == length(@rows)}
                    class="checkbox checkbox-xs"
                  />
                </th>
                <th
                  :if={@geocoding}
                  class="px-3 py-2.5 text-xs uppercase tracking-wider text-left text-base-content/50 w-4/12"
                >
                  {t(@locale, "points.index.address", %{})}
                </th>
                <th class="px-3 py-2.5 text-xs uppercase tracking-wider text-base-content/50 text-right w-1/12">
                  {t(@locale, "points.index.speed", %{})}
                </th>
                <th class="px-3 py-2.5 text-xs uppercase tracking-wider text-base-content/50 w-3/12">
                  {t(@locale, "points.index.coordinates", %{})}
                </th>
                <th class="px-3 py-2.5 text-xs uppercase tracking-wider text-base-content/50 w-3/12">
                  <.link
                    patch={PointListControls.order_url(@query)}
                    class="inline-flex items-center gap-1 link link-hover font-bold"
                  >
                    {t(@locale, "points.index.recorded_at", %{})}<.icon
                      name={if @query["order_by"] == "asc", do: "chevron-up", else: "chevron-down"}
                      class="w-4 h-4 inline-block"
                    />
                  </.link>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={point <- @rows}
                id={"point_#{point.id}"}
                class="hover:bg-base-200/50 transition-colors"
              >
                <td class="px-3 py-2 w-10">
                  <input
                    type="checkbox"
                    id={"point_ids_#{point.id}"}
                    name="point_ids[]"
                    value={point.id}
                    multiple="multiple"
                    form="bulk_destroy_form"
                    aria-label={"#{t(@locale,"points.index.points",%{})} #{point.id}"}
                    phx-click="select_point"
                    phx-value-id={point.id}
                    checked={MapSet.member?(@selected, point.id)}
                    class="checkbox checkbox-xs"
                  />
                </td>
                <td
                  :if={@geocoding}
                  class="px-3 py-2 text-sm text-left text-base-content/60"
                  style="overflow: visible;"
                >
                  <span
                    :if={PointListFormat.address(point) != ""}
                    class="tooltip tooltip-top cursor-help"
                    data-tip={PointListFormat.address(point)}
                  ><span class="block">{PointListFormat.address(point)}</span></span>
                </td>
                <td class={"px-3 py-2 text-sm text-right tabular-nums font-medium whitespace-nowrap " <> PointListFormat.speed_class(point.velocity)}>
                  {PointListFormat.velocity(point.velocity, @unit)}
                </td>
                <td class="px-3 py-2 text-sm tabular-nums text-base-content/50 whitespace-nowrap">
                  {PointListFormat.coordinates(point)}
                </td>
                <td class="px-3 py-2 text-sm tabular-nums whitespace-nowrap">
                  <.human_datetime_with_seconds locale={@locale} at={point.recorded} />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </form>
    </div>
    """
  end
end
