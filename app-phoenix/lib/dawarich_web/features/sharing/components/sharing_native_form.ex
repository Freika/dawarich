defmodule DawarichWeb.SharingNativeForm do
  @moduledoc false
  use DawarichWeb, :html
  attr :resource, :map, required: true
  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :values, :map, required: true
  attr :user, :any, required: true

  def form(assigns) do
    today =
      Dawarich.UserTimeZone.local(
        Dawarich.UserSettings.get(assigns.user),
        NaiveDateTime.utc_now()
      ).local
      |> NaiveDateTime.to_date()

    assigns = assign(assigns, today: today, type: Atom.to_string(assigns.resource.type))

    ~H"""
    <form id="sharing-form" phx-submit="sharing_create" class="space-y-4 min-w-0">
      <div :if={@resource.type == :timeline} class="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <label :for={key <- ~w(start_date end_date)} class="form-control min-w-0">
          <span>{s(@locale, @type, key)}</span>
          <input
            type="date"
            name={"shared_link[#{key}]"}
            value={@values[key] || to_string(@page[key |> String.to_existing_atom()] || @today)}
            required
            class="input input-bordered w-full min-w-0"
          />
        </label>
      </div>
      <label class="form-control min-w-0">
        <span>{s(@locale, @type, "magic_phrase_optional")}</span>
        <input
          id="native-share-phrase"
          type="text"
          name="shared_link[magic_phrase]"
          value=""
          autocomplete="off"
          phx-hook="SharingPhrase"
          data-url="/native/sharing/phrase"
          class="input input-bordered w-full min-w-0"
        />
        <span class="text-xs">{s(@locale, @type, "leave_blank_to_share_without_a_phrase_or_use_the")}</span>
      </label>
      <label class="form-control min-w-0">
        <span>{t(@locale, "shared_links.expires_field.expires_optional", %{})}</span>
        <input
          type="date"
          name="shared_link[expires_at]"
          min={Date.to_iso8601(Date.add(@today, 1))}
          value={@values["expires_at"] || Date.to_iso8601(Date.add(@today, 7))}
          class="input input-bordered w-full min-w-0"
        />
        <span class="text-xs">{t(
          @locale,
          "shared_links.expires_field.stays_active_through_the_end_of_the_day_before_the",
          %{}
        )}</span>
      </label>
      <label
        :if={
          @resource.type == :trip and
            Dawarich.SharedLinks.FamilyAudience.family_id(@user.id, DateTime.utc_now())
        }
        class="form-control min-w-0"
      >
        <span>{t(@locale, "shared_links.family.audience", %{})}</span>
        <select name="shared_link[audience]" class="select select-bordered min-w-0">
          <option
            :for={value <- ~w(public family)}
            value={value}
            selected={@values["audience"] == value}
          >
            {t(
              @locale,
              "shared_links.family." <> if(value == "family", do: "only", else: "public_link"),
              %{}
            )}
          </option>
        </select>
      </label>
      <label
        :for={{key, checked} <- sections(@resource.type)}
        class="flex flex-wrap items-center gap-3 min-w-0"
      >
        <input type="hidden" name={"shared_link[settings][#{key}]"} value="0" />
        <input
          type="checkbox"
          name={"shared_link[settings][#{key}]"}
          value="1"
          checked={
            get_in(@values, ["settings", key]) == "1" or
              (!is_map_key(@values, "settings") and checked)
          }
          class="checkbox"
        />
        <span class="min-w-0">{s(@locale, @type, label(@resource.type, key))}</span>
      </label>
      <button
        type="submit"
        phx-disable-with={s(@locale, @type, "create_share_link")}
        class="btn btn-primary h-auto whitespace-normal"
      >{s(@locale, @type, "create_share_link")}</button>
    </form>
    """
  end

  defp sections(:live), do: [{"show_route", false}]
  defp sections(:timeline), do: [{"show_photos", false}]
  defp sections(:track), do: [{"show_photos", false}, {"show_stats", false}]

  defp sections(:trip),
    do: [
      {"show_route", true},
      {"show_stats", true},
      {"show_days", true},
      {"show_day_notes", false},
      {"show_description", true},
      {"show_photos", false}
    ]

  defp sections(_), do: []
  defp label(:live, "show_route"), do: "share_the_route"
  defp label(:trip, "show_route"), do: "route_map"
  defp label(:trip, "show_stats"), do: "stats_countries_distance_duration"
  defp label(:trip, "show_days"), do: "day_by_day_breakdown"
  defp label(:trip, "show_day_notes"), do: "per_day_notes"
  defp label(:trip, "show_description"), do: "trip_description"
  defp label(:trip, "show_photos"), do: "photos_on_map"
  defp label(_, key), do: key
  defp s(locale, type, key), do: t(locale, "shared_links.modal_#{type}_create_form." <> key, %{})
end
