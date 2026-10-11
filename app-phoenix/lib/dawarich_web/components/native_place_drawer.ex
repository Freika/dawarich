defmodule DawarichWeb.NativePlaceDrawer do
  @moduledoc false
  use DawarichWeb, :html
  attr :detail, :map, default: nil
  attr :locale, :string, required: true
  def drawer(%{detail: nil} = assigns), do: ~H""

  def drawer(assigns) do
    ~H"""
    <section
      id="native-place-drawer"
      class="absolute right-0 top-32 bottom-0 z-20 w-96 max-w-full min-w-0 overflow-y-auto bg-base-100 p-4 space-y-4"
      aria-labelledby="native-place-title"
    >
      <header class="flex min-w-0 gap-2 items-start">
        <h2
          id="native-place-title"
          class="place-drawer__name text-xl font-bold min-w-0 flex-1 [overflow-wrap:anywhere]"
        >
          {@detail.name}
        </h2>
        <button
          type="button"
          class="btn btn-sm btn-ghost"
          phx-click="place:detail:close"
          aria-label={t(@locale, "map.maplibre.settings_panel.close", %{})}
        >✕</button>
      </header>
      <p class="[overflow-wrap:anywhere]">
        {Enum.join(Enum.reject([@detail.city, @detail.country], &is_nil/1), ", ")}
      </p>
      <p>{t(@locale, "places.drawer.source", %{})} {source(@locale, @detail.source)}</p>
      <dl class="flex flex-wrap min-w-0 gap-4">
        <div>
          <dt>{t(@locale, "places.drawer.visit_count", %{count: @detail.visit_count})}</dt><dd data-visit-count>
            {@detail.visit_count}
          </dd>
        </div>
        <div>
          <dt>{t(@locale, "places.drawer.total_hours", %{})}</dt><dd>
            {:erlang.float_to_binary(@detail.total_minutes / 60, decimals: 1)}
          </dd>
        </div>
        <div>
          <dt>{t(@locale, "places.drawer.avg_dwell", %{})}</dt><dd>
            {duration(@locale, average(@detail))}
          </dd>
        </div>
      </dl>
      <ul class="flex flex-wrap gap-2 min-w-0">
        <li
          :for={tag <- @detail.tags}
          class="place-drawer__tag-chip badge h-auto min-w-0 [overflow-wrap:anywhere]"
        >
          {tag.name}
        </li>
      </ul>
      <p :if={@detail.tags == []}>{t(@locale, "places.drawer.no_tags", %{})}</p>
      <form id="native-place-note" phx-submit="place:detail:save" class="space-y-2 min-w-0">
        <label for="native-place-note-input">{t(@locale, "places.drawer.notes", %{})}</label>
        <textarea
          id="native-place-note-input"
          name="place[note]"
          rows="3"
          class="textarea textarea-bordered w-full"
        >{@detail.note}</textarea>
        <button
          type="submit"
          class="btn btn-primary whitespace-normal"
          phx-disable-with={t(@locale, "places.drawer.save", %{})}
        >{t(@locale, "places.drawer.save", %{})}</button>
      </form>
      <h3 class="font-semibold">{t(@locale, "places.drawer.recent_visits", %{})}</h3>
      <ul class="min-w-0">
        <li :for={visit <- @detail.visits} class="my-2 [overflow-wrap:anywhere]">
          <span class="place-drawer__visit-name">{visit.name}</span> {DawarichWeb.HumanDatetime.text(
            @locale,
            visit.started
          )} → {DawarichWeb.HumanDatetime.text(@locale, visit.ended)}
          <span>{duration(@locale, visit.duration)}</span>
        </li>
      </ul>
      <p :if={@detail.visits == []}>{t(@locale, "places.drawer.no_visits_yet", %{})}</p>
      <footer class="flex flex-wrap min-w-0 gap-2">
        <button
          type="button"
          class="btn whitespace-normal"
          phx-click="place:edit"
          phx-value-id={@detail.id}
        >{t(@locale, "places.drawer.edit", %{})}</button>
        <button
          type="button"
          class="btn btn-error whitespace-normal"
          phx-click="place:detail:delete"
          data-confirm={t(@locale, "places.drawer.delete_this_place_this_cannot_be_undone", %{})}
        >{t(@locale, "places.drawer.delete", %{})}</button>
      </footer>
    </section>
    """
  end

  defp average(%{visit_count: 0}), do: 0
  defp average(detail), do: Integer.floor_div(detail.total_minutes, detail.visit_count)

  defp duration(locale, minutes),
    do:
      t(locale, "units.hours_minutes_compact", %{
        hours: div(minutes, 60),
        minutes: rem(minutes, 60)
      })

  defp source(_, nil), do: ""
  defp source(locale, value), do: t(locale, "enums.place.source." <> value, %{})
end
