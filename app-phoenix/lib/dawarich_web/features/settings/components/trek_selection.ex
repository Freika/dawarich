defmodule DawarichWeb.TrekSelection do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.Translate
  alias Dawarich.Imports.Trek.Sources

  def native_form(assigns) do
    ~H"""
    <div class="container max-w-3xl mx-auto px-4 my-8">
      <DawarichWeb.ListParts.page_header title={label(@locale, "title")} />
      <p class="text-base-content/60 mb-6">{label(@locale, "subtitle")}</p>
      <form
        id="native-trek-trips"
        action={"/settings/trek_sources/#{@source.id}/import_trips"}
        accept-charset="UTF-8"
        method="post"
        phx-submit="import"
        class="space-y-3"
      >
        <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
        <p :if={@loading} role="status" class="text-base-content/60">
          {Translate.t(@locale, "javascript.common.loading", %{})}
        </p>
        <label
          :for={trip <- @trips}
          class={"flex items-start gap-3 rounded-box border border-base-content/10 bg-base-200 p-4 " <> if(Sources.selectable?(trip), do: "cursor-pointer hover:border-primary/50", else: "opacity-60")}
        >
          <input
            type="checkbox"
            name="trip_ids[]"
            id={"native-trek-trip-#{trip["id"]}"}
            value={to_string(trip["id"])}
            checked={
              if(to_string(trip["id"]) in @selected and Sources.selectable?(trip), do: "checked")
            }
            disabled={if(not Sources.selectable?(trip), do: "disabled")}
            class="checkbox checkbox-primary mt-1"
          />
          <span>
            <span class="font-semibold block">{title(trip, @locale)}</span>
            <span :if={dated?(trip)} class="text-sm text-base-content/60">{trip["start_date"]} – {trip[
              "end_date"
            ]}</span>
            <span :if={not dated?(trip)} class="text-sm text-base-content/60">{label(
              @locale,
              "dates_required"
            )}</span>
            <span :if={trip["archived"] not in [nil, false]} class="badge badge-ghost badge-sm ml-2">{label(
              @locale,
              "archived"
            )}</span>
          </span>
        </label>
        <div class="flex gap-2 pt-3">
          <input
            type="submit"
            name="commit"
            value={label(@locale, "import_selected")}
            class="btn btn-primary"
            disabled={@loading}
            phx-disable-with={label(@locale, "import_selected")}
          />
          <.link navigate="/settings/integrations?service=trek" class="btn btn-ghost">{label(
            @locale,
            "back"
          )}</.link>
        </div>
      </form>
    </div>
    """
  end

  defp dated?(trip), do: Sources.selectable?(Map.put(trip, "archived", false))
  defp title(%{"title" => title}, _) when is_binary(title) and title != "", do: title
  defp title(_, locale), do: label(locale, "untitled_trip")

  defp label(locale, key),
    do: Translate.t(locale, "settings.trek_sources.select_trips." <> key, %{})
end
