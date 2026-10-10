defmodule DawarichWeb.NativeSelectionActions do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.Icon
  alias Phoenix.LiveView.JS

  @max 500

  attr :id, :string, required: true
  attr :ids, :list, required: true
  attr :actions, :list, default: ~w(merge delete)
  attr :cancel, :string, required: true
  attr :locale, :string, required: true

  def bar(assigns) do
    count = length(assigns.ids)

    assigns =
      assign(assigns,
        count: count,
        over: count > @max,
        label:
          if(count > @max,
            do:
              t(assigns.locale, "javascript.timeline.selected_with_max", %{
                count: count,
                max: @max
              }),
            else: t(assigns.locale, "javascript.timeline.selected", %{count: count})
          )
      )

    ~H"""
    <div id={@id} class="selection-bar flex flex-wrap items-center gap-2 min-w-0" role="toolbar">
      <span class="selection-bar__count min-w-0">{@label}</span>
      <span class="selection-bar__actions flex flex-wrap gap-1">
        <button
          :for={action <- @actions}
          type="button"
          class={["btn btn-xs", action == "delete" && "btn-error"]}
          data-selection-action={action}
          disabled={@over or @count < minimum(action)}
          data-confirm={
            action == "delete" && b(@locale, "remove_the_visit_grouping_your_location_points_stay")
          }
          phx-click={JS.push("visits:bulk", value: %{action: action, ids: @ids})}
        >
          {label(@locale, action)}
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-xs btn-square"
          phx-click={@cancel}
          aria-label={b(@locale, "cancel")}
        >
          <Icon.icon name="x" class="w-3.5 h-3.5" />
        </button>
      </span>
    </div>
    """
  end

  defp minimum("merge"), do: 2
  defp minimum(_action), do: 1

  defp label(locale, "merge"), do: b(locale, "merge")
  defp label(locale, "delete"), do: b(locale, "delete")
  defp label(locale, "confirm"), do: t(locale, "javascript.common.confirm", %{})
  defp label(locale, "decline"), do: t(locale, "javascript.common.decline", %{})

  defp b(locale, key), do: t(locale, "map.timeline_feeds.selection_bar." <> key, %{})
end
