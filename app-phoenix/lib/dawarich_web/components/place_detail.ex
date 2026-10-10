defmodule DawarichWeb.PlaceDetail do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.CoreComponents
  alias DawarichWeb.OrdinaryFormComponents, as: Ordinary
  attr :detail, :map, required: true
  attr :state, :any, required: true
  attr :locale, :string, required: true

  def panel(assigns) do
    assigns =
      assign(assigns, :form, to_form(assigns.state.changeset, as: :place, id: assigns.state.id))

    ~H"""
    <Ordinary.dialog
      id={@state.id <> "-dialog"}
      title={@detail.name}
      cancel_event="cancel_form"
      close_label={t(@locale, "settings.users.index.cancel", %{})}
    >
      <p class="[overflow-wrap:anywhere]">
        {Enum.join(Enum.reject([@detail.city, @detail.country], &is_nil/1), ", ")}
      </p>
      <p>{t(@locale, "places.drawer.source", %{})} {source(@locale, @detail.source)}</p>
      <dl class="flex flex-wrap gap-4 my-3 min-w-0">
        <div>
          <dt>{t(@locale, "places.drawer.visit_count", %{count: @detail.visit_count})}</dt><dd data-visit-count>
            {@detail.visit_count}
          </dd>
        </div>
        <div>
          <dt>{t(@locale, "places.drawer.total_hours", %{})}</dt><dd data-total-minutes={
            @detail.total_minutes
          }>
            {hours(@detail.total_minutes)}
          </dd>
        </div>
        <div>
          <dt>{t(@locale, "places.drawer.avg_dwell", %{})}</dt><dd>{average(@detail)}</dd>
        </div>
      </dl>
      <ul class="flex flex-wrap gap-2">
        <li :for={tag <- @detail.tags} class="badge h-auto [overflow-wrap:anywhere]">
          {tag.icon} {tag.name}
        </li>
      </ul>
      <p :if={@detail.tags == []}>{t(@locale, "places.drawer.no_tags", %{})}</p>
      <form id={@state.id} phx-submit="save_place_note">
        <input type="hidden" name="generation" value={@state.generation} />
        <Ordinary.summary state={@state} />
        <.input
          field={@form[:note]}
          type="textarea"
          rows="3"
          label={t(@locale, "places.drawer.notes", %{})}
        />
        <button
          type="submit"
          class="btn btn-primary"
          disabled={@state.status != :idle}
          phx-disable-with={t(@locale, "places.drawer.save", %{})}
        >{t(@locale, "places.drawer.save", %{})}</button>
        <button
          :if={@state.status == :partial}
          type="button"
          class="btn"
          phx-click="recover_place_note"
        >{t(@locale, "javascript.messages.retry", %{})}</button>
      </form>
      <h3 class="font-semibold mt-4">{t(@locale, "places.drawer.recent_visits", %{})}</h3>
      <ul class="min-w-0">
        <li :for={visit <- @detail.visits} class="my-2 [overflow-wrap:anywhere]">
          <span>{visit.name}</span> {DawarichWeb.HumanDatetime.text(@locale, visit.started)} → {DawarichWeb.HumanDatetime.text(
            @locale,
            visit.ended
          )} <span>{visit.duration}</span>
        </li>
      </ul>
      <p :if={@detail.visits == []}>{t(@locale, "places.drawer.no_visits_yet", %{})}</p>
      <div class="flex flex-wrap gap-2 mt-3">
        <button type="button" class="btn" phx-click="open_edit" phx-value-id={@detail.id}>{t(
          @locale,
          "places.drawer.edit",
          %{}
        )}</button>
        <a class="btn" href={"/places/#{@detail.id}"}>{t(
          @locale,
          "trips.source_itinerary.show_on_map",
          %{}
        )}</a>
        <button
          type="button"
          class="btn btn-error"
          phx-click="request_delete"
          phx-value-id={@detail.id}
        >{t(@locale, "places.drawer.delete", %{})}</button>
      </div>
    </Ordinary.dialog>
    """
  end

  defp source(_, nil), do: ""
  defp source(locale, value), do: t(locale, "enums.place.source." <> value, %{})
  defp hours(total), do: :erlang.float_to_binary(total / 60, decimals: 1)
  defp average(%{visit_count: 0}), do: 0
  defp average(detail), do: Integer.floor_div(detail.total_minutes, detail.visit_count)
end
