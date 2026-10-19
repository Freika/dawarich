defmodule DawarichWeb.NativeSelectionActions do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.Icon
  alias Phoenix.LiveView.JS

  @max 500

  attr :ids, :list, default: nil
  attr :csrf, :string, default: ""
  attr :cancel, :string, required: true
  attr :locale, :string, required: true

  def bar(assigns) do
    ids = assigns.ids || []
    count = length(ids)
    over = count > @max

    assigns =
      assign(assigns,
        list: ids,
        max: @max,
        merge_off: over or count < 2,
        delete_off: over or count < 1,
        label: label(assigns.locale, assigns.ids, count, over)
      )

    ~H"""
    <div
      {if(@ids, do: [id: "native-timeline-selection"], else: [])}
      data-max-bulk-visits={@max}
      class="selection-bar"
      hidden={is_nil(@ids)}
    >
      <span class="selection-bar__count">{@label}</span>
      <span class="selection-bar__actions">
        <form
          class="selection-bar__form"
          action="/visits/merge"
          accept-charset="UTF-8"
          method="post"
          phx-submit={JS.push("visits:bulk", value: %{action: "merge", ids: @list})}
        >
          <input type="hidden" name="authenticity_token" value={@csrf} />
          <button
            type="submit"
            class="selection-bar__action selection-bar__merge"
            title={b(@locale, "combine_the_selected_visits_into_one")}
            disabled={@merge_off}
          >
            {b(@locale, "merge")}
          </button>
        </form>
        <form
          class="selection-bar__form"
          action="/visits/bulk_destroy"
          accept-charset="UTF-8"
          method="post"
          phx-submit={JS.push("visits:bulk", value: %{action: "delete", ids: @list})}
        >
          <input type="hidden" name="_method" value="delete" />
          <input type="hidden" name="authenticity_token" value={@csrf} />
          <button
            type="submit"
            class="selection-bar__action selection-bar__delete"
            data-confirm={b(@locale, "remove_the_visit_grouping_your_location_points_stay")}
            title={b(@locale, "remove_the_visit_grouping_your_location_points_stay")}
            disabled={@delete_off}
          >
            {b(@locale, "delete")}
          </button>
        </form>
        <button
          type="button"
          class="selection-bar__cancel"
          title={b(@locale, "cancel")}
          aria-label={b(@locale, "cancel")}
          phx-click={@cancel}
        >
          <Icon.icon name="x" class="w-3.5 h-3.5" />
        </button>
      </span>
    </div>
    """
  end

  defp label(locale, nil, _count, _over), do: b(locale, "selected")

  defp label(locale, _ids, count, true),
    do: t(locale, "javascript.timeline.selected_with_max", %{count: count, max: @max})

  defp label(locale, _ids, count, false),
    do: t(locale, "javascript.timeline.selected", %{count: count})

  defp b(locale, key), do: t(locale, "map.timeline_feeds.selection_bar." <> key, %{})
end
