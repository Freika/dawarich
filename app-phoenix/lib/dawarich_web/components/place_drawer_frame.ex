defmodule DawarichWeb.PlaceDrawerFrame do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1]

  alias Dawarich.ReleaseMigrations.Effects.Support.{Ruby, RubyFloat}
  alias DawarichWeb.{LocalizedDate, LocalizedTime}

  attr :drawer, :map, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true

  def frame(assigns) do
    ~H"""
    <turbo-frame id="place-drawer">
      <.drawer drawer={@drawer} locale={@locale} csrf={@csrf} />
    </turbo-frame>
    """
  end

  attr :drawer, :map, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true

  def drawer(assigns) do
    drawer = assigns.drawer

    assigns =
      assign(assigns,
        icon: drawer.tags |> List.first(%{}) |> Map.get(:icon),
        location: [drawer.city, drawer.country] |> Enum.reject(&Ruby.blank?/1) |> Enum.join(", "),
        total_hours: RubyFloat.to_s(Dawarich.RubyFloat.round(drawer.total_minutes / 60.0, 1)),
        average: duration(assigns.locale, average(drawer))
      )

    ~H"""
    <div class="place-drawer place-drawer--open" data-place-id={@drawer.id}>
      <header class="place-drawer__header">
        <div class="place-drawer__icon">
          <%= if Ruby.present?(@icon) do %>
            <span class="text-2xl leading-none">{@icon}</span>
          <% else %>
            <.icon name="map-pin" class="w-6 h-6" />
          <% end %>
        </div>
        <div class="place-drawer__titles">
          <h2 class="place-drawer__name">
            {@drawer.name}
            <span
              :if={@drawer.locked}
              class="place-drawer__name-lock"
              title={
                t(@locale, "places.drawer.manual_name_title", %{default_name: "Suggested place"})
              }
              data-testid="place-name-lock"
            ><.icon name="lock" class="w-4 h-4 inline" /></span>
          </h2>
          <p :if={@location != ""} class="place-drawer__location">{@location}</p>
          <p class="place-drawer__source" phx-no-format>{t(@locale, "places.drawer.source", %{})} {source(@locale, @drawer.source)}</p>
        </div>
        <button
          type="button"
          class="btn btn-ghost btn-sm btn-circle"
          aria-label={t(@locale, "map.maplibre.settings_panel.close", %{})}
          data-action="place-detail#close"
        >✕</button>
      </header>

      <section class="place-drawer__stats">
        <div class="place-drawer__stat">
          <span class="place-drawer__stat-value">{@drawer.visit_count}</span>
          <span class="place-drawer__stat-label">{t(@locale, "places.drawer.visit_count", %{
            count: @drawer.visit_count
          })}</span>
        </div>
        <div class="place-drawer__stat">
          <span class="place-drawer__stat-value">{@total_hours}</span>
          <span class="place-drawer__stat-label">{t(@locale, "places.drawer.total_hours", %{})}</span>
        </div>
        <div class="place-drawer__stat">
          <span class="place-drawer__stat-value">{@average}</span>
          <span class="place-drawer__stat-label">{t(@locale, "places.drawer.avg_dwell", %{})}</span>
        </div>
      </section>

      <section class="place-drawer__tags">
        <%= if @drawer.tags != [] do %>
          <ul class="place-drawer__tag-list">
            <li
              :for={tag <- @drawer.tags}
              class="place-drawer__tag-chip"
              style={chip_style(tag.color)}
            >
              {tag.name}
            </li>
          </ul>
        <% else %>
          <p class="place-drawer__tags-empty">{t(@locale, "places.drawer.no_tags", %{})}</p>
        <% end %>
      </section>

      <section class="place-drawer__notes">
        <form
          data-turbo-frame="place-drawer"
          action={"/places/#{@drawer.id}"}
          accept-charset="UTF-8"
          method="post"
        >
          <input type="hidden" name="_method" value="patch" /><input
            type="hidden"
            name="authenticity_token"
            value={@csrf}
          />
          <label for="place-drawer-note" class="place-drawer__notes-label">{t(
            @locale,
            "places.drawer.notes",
            %{}
          )}</label>
          <textarea
            id="place-drawer-note"
            rows="3"
            class="place-drawer__notes-input"
            name="place[note]"
            phx-no-format
          >{"\n" <> (@drawer.note || "")}</textarea>
          <input
            type="submit"
            name="commit"
            value={t(@locale, "places.drawer.save", %{})}
            class="place-drawer__notes-submit"
            data-disable-with={t(@locale, "places.drawer.save", %{})}
          />
        </form>
      </section>

      <section class="place-drawer__visits">
        <h3 class="place-drawer__visits-heading">{t(@locale, "places.drawer.recent_visits", %{})}</h3>
        <%= if @drawer.visits != [] do %>
          <ul class="place-drawer__visits-list">
            <li :for={visit <- @drawer.visits} class="place-drawer__visit">
              <span class="place-drawer__visit-name">{visit.name}</span>
              <span class="place-drawer__visit-time">{time_range(@locale, visit)}</span>
              <span class="place-drawer__visit-duration">{duration(@locale, visit.duration)}</span>
            </li>
          </ul>
        <% else %>
          <p class="place-drawer__visits-empty">{t(@locale, "places.drawer.no_visits_yet", %{})}</p>
        <% end %>
      </section>

      <footer class="place-drawer__actions">
        <button
          type="button"
          class="place-drawer__action place-drawer__action--edit"
          data-action="maps--maplibre#handleEdit"
          data-id={@drawer.id}
          data-entity-type="place"
        >{t(@locale, "places.drawer.edit", %{})}</button>
        <button type="button" class="place-drawer__action place-drawer__action--merge" disabled>{t(
          @locale,
          "places.drawer.merge",
          %{}
        )}</button>
        <form
          data-action="turbo:submit-end->place-detail#deleted"
          data-place-detail-id-param={@drawer.id}
          class="button_to"
          method="post"
          action={"/places/#{@drawer.id}"}
        >
          <input type="hidden" name="_method" value="delete" /><button
            class="place-drawer__action place-drawer__action--delete"
            data-turbo-confirm={
              t(@locale, "places.drawer.delete_this_place_this_cannot_be_undone", %{})
            }
            type="submit"
          >{t(@locale, "places.drawer.delete", %{})}</button><input
            type="hidden"
            name="authenticity_token"
            value={@csrf}
          />
        </form>
      </footer>
    </div>
    """
  end

  defp source(locale, nil),
    do:
      "{" <>
        Enum.map_join(~w(manual photon gpx_waypoint), ", ", fn key ->
          key <> ": " <> Jason.encode!(t(locale, "enums.place.source." <> key, %{}))
        end) <> "}"

  defp source(locale, value), do: t(locale, "enums.place.source." <> value, %{})

  defp chip_style(color),
    do: if(Ruby.present?(color), do: "background-color: #{color};", else: "")

  defp average(%{visit_count: 0}), do: 0
  defp average(%{visit_count: count, total_minutes: total}), do: Integer.floor_div(total, count)

  defp duration(locale, minutes),
    do:
      t(locale, "units.hours_minutes_compact", %{
        hours: Integer.floor_div(minutes, 60),
        minutes: Integer.mod(minutes, 60)
      })

  defp time_range(locale, visit),
    do:
      Enum.join(
        [
          LocalizedTime.l(locale, visit.started, "hour_minute"),
          t(locale, "places.drawer.rarr", %{}),
          LocalizedTime.l(locale, visit.ended, "hour_minute"),
          t(locale, "places.drawer.on", %{}),
          LocalizedDate.l(locale, NaiveDateTime.to_date(visit.started), "iso")
        ],
        " "
      )
end
