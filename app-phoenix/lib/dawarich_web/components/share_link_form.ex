defmodule DawarichWeb.ShareLinkForm do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.UserTimeZone

  embed_templates "share_link_form/*"

  def create(assigns) do
    today =
      UserTimeZone.local(assigns.ctx.settings, DateTime.to_naive(assigns.ctx.now)).local
      |> NaiveDateTime.to_date()

    assigns = assigns |> assign(:today, today) |> assign(:phrase, assigns.ctx.phrase.())
    create_form(assigns)
  end

  defp s(ctx, type, key), do: t(ctx.locale, "shared_links.modal_#{type}_create_form." <> key, %{})
  defp expiry(ctx, key), do: t(ctx.locale, "shared_links.expires_field." <> key, %{})

  defp family(ctx, key), do: t(ctx.locale, "shared_links.family." <> key, %{})

  defp audiences(ctx),
    do: [{"public", family(ctx, "public_link")}, {"family", family(ctx, "only")}]

  defp sections do
    [
      {"show_route", "route_map", true},
      {"show_stats", "stats_countries_distance_duration", true},
      {"show_days", "day_by_day_breakdown", true},
      {"show_day_notes", "per_day_notes", false},
      {"show_description", "trip_description", true},
      {"show_photos", "photos_on_map", false}
    ]
  end
end
