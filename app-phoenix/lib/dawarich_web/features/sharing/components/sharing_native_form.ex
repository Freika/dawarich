defmodule DawarichWeb.SharingNativeForm do
  @moduledoc false
  use DawarichWeb, :html
  embed_templates "sharing_native_form/*"
  attr :resource, :map, required: true
  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :values, :map, required: true
  attr :user, :any, required: true
  attr :today, :any, default: nil

  def form(assigns) do
    today =
      assigns.today ||
        Dawarich.UserTimeZone.local(
          Dawarich.UserSettings.get(assigns.user),
          NaiveDateTime.utc_now()
        ).local
        |> NaiveDateTime.to_date()

    assigns =
      assign(assigns,
        today: today,
        type: Atom.to_string(assigns.resource.type),
        family:
          assigns.resource.type == :trip &&
            Dawarich.SharedLinks.FamilyAudience.family_id(assigns.user.id, DateTime.utc_now())
      )

    controls(assigns)
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

  defp checked(values, key, default),
    do:
      if(is_map_key(values, "settings"),
        do: get_in(values, ["settings", key]) in ["1", true],
        else: default
      )

  defp close(%{type: :trip, id: id}), do: "/trips/#{id}"
  defp close(_), do: "/map/v2"

  defp warning(locale) do
    location =
      s(locale, "live", "current_location_in_real_time")
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    t(locale, "shared_links.modal_live_create_form.this_shares_your_location_with_anyone_html", %{
      location: Phoenix.HTML.raw("<strong>#{location}</strong>")
    })
    |> Phoenix.HTML.raw()
  end
end
