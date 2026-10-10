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
  attr :csrf, :string, required: true

  def table(assigns) do
    assigns =
      assign(
        assigns,
        :selection_key,
        assigns.query |> Enum.sort() |> URI.encode_query() |> Base.url_encode64(padding: false)
      )

    ~H"""
    <div id="points">
      <div
        id={"points-page-#{@selection_key}"}
        data-controller="checkbox-select-all"
        phx-hook="RailsStimulus"
        phx-update="ignore"
        inert
      >
        <fieldset disabled data-rails-form-ready class="contents">
          <form
            action={PointListControls.bulk_action(@query)}
            id="bulk_destroy_form"
            accept-charset="UTF-8"
            method="post"
          >
            <input type="hidden" name="_method" value="delete" /><input
              type="hidden"
              name="authenticity_token"
              value={@csrf}
            />
            <input
              type="submit"
              name="commit"
              value={t(@locale, "points.index.delete_selected", %{})}
              class="btn btn-error btn-sm mb-3"
              data-turbo-confirm={t(@locale, "points.index.are_you_sure", %{})}
              data-checkbox-select-all-target="deleteButton"
              style="display: none;"
              data-disable-with={t(@locale, "points.index.delete_selected", %{})}
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
                        data-checkbox-select-all-target="parent"
                        data-action="change->checkbox-select-all#toggleChildren"
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
                      <a
                        href={PointListControls.order_url(@query)}
                        class="inline-flex items-center gap-1 link link-hover font-bold"
                      >
                        {t(@locale, "points.index.recorded_at", %{})}
                        <.icon
                          name={
                            if @query["order_by"] == "asc", do: "chevron-up", else: "chevron-down"
                          }
                          class="w-4 h-4 inline-block"
                        />
                      </a>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <.row
                    :for={point <- @rows}
                    locale={@locale}
                    point={point}
                    geocoding={@geocoding}
                    unit={@unit}
                  />
                </tbody>
              </table>
            </div>
          </form>
        </fieldset>
      </div>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :point, :map, required: true
  attr :geocoding, :boolean, required: true
  attr :unit, :string, required: true

  def row(assigns) do
    assigns = assign(assigns, :address, PointListFormat.address(assigns.point))

    ~H"""
    <tr id={"point_#{@point.id}"} class="hover:bg-base-200/50 transition-colors">
      <td class="px-3 py-2 w-10">
        <input
          type="checkbox"
          name="point_ids[]"
          id={"point_ids_#{@point.id}"}
          value={@point.id}
          multiple="multiple"
          form="bulk_destroy_form"
          class="checkbox checkbox-xs"
          data-checkbox-select-all-target="child"
          data-action="change->checkbox-select-all#toggleParent"
        />
      </td>
      <td
        :if={@geocoding}
        class="px-3 py-2 text-sm text-left text-base-content/60"
        style="overflow: visible;"
      >
        <span :if={@address != ""} class="tooltip tooltip-top cursor-help" data-tip={@address}><span class="block">{@address}</span></span>
      </td>
      <td class={"px-3 py-2 text-sm text-right tabular-nums font-medium whitespace-nowrap #{PointListFormat.speed_class(@point.velocity)}"}>
        {PointListFormat.velocity(@point.velocity, @unit)}
      </td>
      <td class="px-3 py-2 text-sm tabular-nums text-base-content/50 whitespace-nowrap">
        {PointListFormat.coordinates(@point)}
      </td>
      <td class="px-3 py-2 text-sm tabular-nums whitespace-nowrap">
        <.human_datetime_with_seconds locale={@locale} at={@point.recorded} />
      </td>
    </tr>
    """
  end
end
