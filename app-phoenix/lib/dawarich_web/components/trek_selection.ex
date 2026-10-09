defmodule DawarichWeb.TrekSelection do
  @moduledoc false
  use DawarichWeb, :html
  import Plug.Conn
  alias DawarichWeb.{Layouts, Locale, LayoutAssigns, Translate}
  alias Dawarich.Imports.Trek.Sources

  def render(conn, source, trips, selected) do
    conn = conn |> fetch_query_params() |> Locale.call([]) |> LayoutAssigns.call([])

    assigns =
      Map.merge(conn.assigns, %{
        __changed__: nil,
        flash: %{},
        page_title:
          Translate.t(conn.assigns.locale, "settings.trek_sources.select_trips.title", %{}),
        navbar:
          Dawarich.Navbar.load(conn.assigns.current_user,
            now: conn.assigns.now,
            self_hosted: conn.assigns.self_hosted
          )
      })

    body = selection_form(Map.merge(assigns, %{source: source, trips: trips, selected: selected}))
    app = Layouts.app(Map.put(assigns, :inner_content, body))
    html = Layouts.root(Map.put(assigns, :inner_content, app)) |> Phoenix.HTML.Safe.to_iodata()
    conn |> put_resp_content_type("text/html") |> send_resp(200, html) |> halt()
  end

  def selection_form(assigns) do
    ~H"""
    <div class="container max-w-3xl mx-auto px-4 my-8">
      <h1 class="text-2xl font-bold">{label(@locale, "title")}</h1>
      <p class="text-base-content/60 mb-6">{label(@locale, "subtitle")}</p>
      <form
        action={"/settings/trek_sources/#{@source.id}/import_trips"}
        method="post"
        data-turbo="false"
        class="space-y-3"
      >
        <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
        <label
          :for={trip <- @trips}
          class={"flex items-start gap-3 rounded-box border border-base-content/10 bg-base-200 p-4 " <> if(Sources.selectable?(trip), do: "cursor-pointer hover:border-primary/50", else: "opacity-60")}
        >
          <input
            type="checkbox"
            name="trip_ids[]"
            value={to_string(trip["id"])}
            checked={to_string(trip["id"]) in @selected and Sources.selectable?(trip)}
            disabled={not Sources.selectable?(trip)}
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
          <input type="submit" value={label(@locale, "import_selected")} class="btn btn-primary" />
          <a href="/settings/integrations?service=trek" class="btn btn-ghost">{label(@locale, "back")}</a>
        </div>
      </form>
    </div>
    """
  end

  def native_form(assigns) do
    ~H"""
    <div class="container max-w-3xl mx-auto px-4 my-8">
      <h1 class="text-2xl font-bold">{label(@locale, "title")}</h1>
      <p class="text-base-content/60 mb-6">{label(@locale, "subtitle")}</p>
      <.form for={@form} id="trek-trips" phx-submit="import" class="space-y-3">
        <input type="hidden" name="selection[trip_ids][]" value="" />
        <label
          :for={trip <- @trips}
          class="flex items-start gap-3 rounded-box border border-base-content/10 bg-base-200 p-4"
        >
          <input
            type="checkbox"
            name="selection[trip_ids][]"
            value={to_string(trip["id"])}
            checked={to_string(trip["id"]) in @selected and Sources.selectable?(trip)}
            disabled={not Sources.selectable?(trip)}
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
        <div class="flex flex-wrap gap-2 pt-3">
          <button
            type="submit"
            class="btn btn-primary"
            phx-disable-with={label(@locale, "import_selected")}
          >{label(@locale, "import_selected")}</button>
          <.link navigate="/settings/integrations?service=trek" class="btn btn-ghost">{label(
            @locale,
            "back"
          )}</.link>
        </div>
      </.form>
    </div>
    """
  end

  defp dated?(trip), do: Sources.selectable?(Map.put(trip, "archived", false))
  defp title(%{"title" => title}, _) when is_binary(title) and title != "", do: title
  defp title(_, locale), do: label(locale, "untitled_trip")

  defp label(locale, key),
    do: Translate.t(locale, "settings.trek_sources.select_trips." <> key, %{})
end
