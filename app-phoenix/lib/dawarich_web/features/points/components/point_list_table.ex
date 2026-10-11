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

  def table(assigns) do
    ~H"""
    <div id="points" class="min-w-0">
      <button
        :if={MapSet.size(@selected) > 0}
        type="button"
        class="btn btn-error btn-sm h-auto whitespace-normal mb-3"
        phx-click="confirm_delete"
      >{t(@locale, "points.index.delete_selected", %{})}</button>
      <div class="border border-base-300 rounded-xl overflow-x-auto max-w-full">
        <table class="table table-sm w-full">
          <thead>
            <tr>
              <th>
                <input
                  type="checkbox"
                  id="select_all_points"
                  aria-label={t(@locale, "points.index.select_all", %{})}
                  phx-click="select_all"
                  checked={@rows != [] and MapSet.size(@selected) == length(@rows)}
                  class="checkbox checkbox-xs"
                />
              </th>
              <th :if={@geocoding}>{t(@locale, "points.index.address", %{})}</th>
              <th>{t(@locale, "points.index.speed", %{})}</th>
              <th>{t(@locale, "points.index.coordinates", %{})}</th>
              <th>
                <.link
                  patch={PointListControls.order_url(@query)}
                  class="inline-flex flex-wrap items-center gap-1"
                >{t(@locale, "points.index.recorded_at", %{})}<.icon
                  name={if @query["order_by"] == "asc", do: "chevron-up", else: "chevron-down"}
                  class="w-4 h-4"
                /></.link>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={point <- @rows} id={"point_#{point.id}"}>
              <td>
                <input
                  type="checkbox"
                  id={"point_ids_#{point.id}"}
                  aria-label={"#{t(@locale,"points.index.points",%{})} #{point.id}"}
                  phx-click="select_point"
                  phx-value-id={point.id}
                  checked={MapSet.member?(@selected, point.id)}
                  class="checkbox checkbox-xs"
                />
              </td>
              <td :if={@geocoding} class="break-words [overflow-wrap:anywhere]">
                {PointListFormat.address(point)}
              </td>
              <td class={PointListFormat.speed_class(point.velocity)}>
                {PointListFormat.velocity(point.velocity, @unit)}
              </td>
              <td class="break-words">{PointListFormat.coordinates(point)}</td>
              <td><.human_datetime_with_seconds locale={@locale} at={point.recorded} /></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
