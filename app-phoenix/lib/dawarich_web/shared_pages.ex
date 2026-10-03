defmodule DawarichWeb.SharedPages do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Head, only: [favicon: 1, pwa_meta: 1]

  alias DawarichWeb.{Assets, Layouts, LocalizedDate, RailsCsrf}

  embed_templates "shared_pages/*"

  @false_values [false, "0", "f", "F", "false", "FALSE", "off", "OFF"]

  def not_found(assigns),
    do:
      notice(
        assign(assigns,
          scope: "shared.links.not_found",
          heading: "this_shared_link_is_no_longer_available",
          body: "the_owner_may_have_revoked_the_link_or_it_may"
        )
      )

  def missing_resource(assigns),
    do:
      notice(
        assign(assigns,
          scope: "shared.links.missing_resource",
          heading: "this_share_is_no_longer_available",
          body: "the_original_content_was_removed_by_the_owner"
        )
      )

  def html(assigns), do: assigns |> document() |> Phoenix.HTML.Safe.to_iodata()

  def title(%{page: :not_found, locale: locale}),
    do: t(locale, "shared.links.not_found.not_found_dawarich", %{})

  def title(%{page: :phrase_prompt, locale: locale}),
    do: t(locale, "shared.links.phrase_prompt.enter_phrase_dawarich", %{})

  def title(%{link: link, locale: locale}),
    do: t(locale, "shared.links.show.name_shared_on_dawarich", %{name: link.name})

  def importmap,
    do: Jason.encode!(%{"imports" => Assets.rails_imports()}, escape: :html_safe)

  def translations(locale), do: Layouts.rails_translations(locale)

  def cta(content, path \\ "/"),
    do:
      "https://dawarich.app#{path}?utm_campaign=cloud&utm_content=#{content}" <>
        "&utm_medium=public_share&utm_source=dawarich_share"

  def form_token(session, id), do: RailsCsrf.masked_form_token(session, "/s/#{id}/unlock", "post")

  def show_route(value) when value in [nil, ""], do: ""
  def show_route(value) when value in @false_values or value === 0 or value === 0.0, do: "false"
  def show_route(_value), do: "true"

  def date_range(locale, from, to) do
    l = &LocalizedDate.l(locale, &1, &2)

    cond do
      from == to ->
        l.(from, "month_day_year")

      {from.year, from.month} == {to.year, to.month} ->
        range(locale, "same_month", l.(from, "month_day"), l.(to, "day_year"))

      from.year == to.year ->
        range(locale, "same_year", l.(from, "month_day"), l.(to, "month_day_year"))

      true ->
        range(locale, "different_years", l.(from, "medium"), l.(to, "medium"))
    end
  end

  defp range(locale, key, from, to),
    do: t(locale, "helpers.shared_links.date_ranges." <> key, %{start_date: from, end_date: to})

  def l(locale, key), do: t(locale, "layouts.shared." <> key, %{})
end
