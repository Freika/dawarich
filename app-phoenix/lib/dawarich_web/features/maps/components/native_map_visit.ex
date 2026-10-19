defmodule DawarichWeb.NativeMapVisit do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias Phoenix.LiveView.JS

  attr :dialog, :map, default: nil
  attr :locale, :string, required: true

  def dialog(%{dialog: nil} = assigns), do: ~H""
  def dialog(%{dialog: %{inline: true}} = assigns), do: ~H""

  def dialog(assigns) do
    ~H"""
    <div id="native-visit-dialog" phx-window-keydown={close()} phx-key="escape">
      <div
        class="modal z-[10000] modal-open"
        role="dialog"
        aria-modal="true"
        phx-mounted={JS.focus_first(to: "#native-visit-form")}
      >
        <div class="modal-box max-w-2xl">
          <h3 class="font-bold text-lg mb-4">
            {if @dialog.id,
              do: t(@locale, "javascript.visits.edit", %{}),
              else: v(@locale, "create_new_visit")}
          </h3>
          <ul :if={@dialog.errors != []} class="alert alert-error mb-4 block" role="alert">
            <li :for={error <- @dialog.errors} class="[overflow-wrap:anywhere]">
              {message(@locale, error)}
            </li>
          </ul>
          <form id="native-visit-form" phx-submit="visit:save">
            <input type="hidden" name="latitude" value={@dialog.form["latitude"]} />
            <input type="hidden" name="longitude" value={@dialog.form["longitude"]} />

            <div class="space-y-4">
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">{v(@locale, "visit_name")}</span>
                </label>
                <input
                  type="text"
                  name="name"
                  placeholder={v(@locale, "enter_visit_name")}
                  aria-label={v(@locale, "visit_name")}
                  class="input input-bordered w-full"
                  value={@dialog.form["name"]}
                  required
                />
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div
                  :for={{name, label} <- [{"started_at", "start_time"}, {"ended_at", "end_time"}]}
                  class="form-control"
                >
                  <label class="label">
                    <span class="label-text font-semibold">{v(@locale, label)}</span>
                  </label>
                  <input
                    type="datetime-local"
                    name={name}
                    max="9999-12-31T23:59"
                    aria-label={v(@locale, label)}
                    class="input input-bordered w-full"
                    value={@dialog.form[name]}
                    required
                  />
                </div>
              </div>
            </div>

            <div class="modal-action">
              <button type="button" class="btn btn-ghost" phx-click={close()}>{v(@locale, "cancel")}</button>
              <button type="submit" class="btn btn-primary">
                {if @dialog.id,
                  do: t(@locale, "javascript.visits.update", %{}),
                  else: v(@locale, "create_visit")}
              </button>
            </div>
          </form>
          <.edit_extras :if={@dialog.id} dialog={@dialog} locale={@locale} />
        </div>
        <div class="modal-backdrop" phx-click={close()}></div>
      </div>
    </div>
    """
  end

  attr :dialog, :map, required: true
  attr :locale, :string, required: true

  defp edit_extras(assigns) do
    ~H"""
    <section :if={@dialog.places != []} class="mt-4 min-w-0">
      <h4 class="font-semibold text-sm">{e(@locale, "attached_place")}</h4>
      <div class="flex flex-wrap gap-2 mt-2">
        <button
          :for={place <- @dialog.places}
          type="button"
          class={[
            "btn btn-xs",
            if(place.id == @dialog.place_id, do: "btn-primary", else: "btn-outline")
          ]}
          phx-click={JS.push("visit:place", value: %{place_id: to_string(place.id)})}
        >
          <span class="[overflow-wrap:anywhere]">{place.name}</span>
        </button>
      </div>
    </section>
    <DawarichWeb.NativeVisitPlaceSearch.search
      search={@dialog[:search]}
      locale={@locale}
    />
    <section class="mt-4 min-w-0">
      <h4 class="font-semibold text-sm">{t(@locale, "places.drawer.notes", %{})}</h4>
      <ul class="space-y-1 mt-2">
        <li
          :for={note <- @dialog.notes}
          class="text-sm whitespace-pre-line [overflow-wrap:anywhere]"
        >
          {note["body"]}
        </li>
      </ul>
      <form id="native-visit-note-form" phx-submit="note:add" class="mt-2 space-y-2">
        <p
          :if={@dialog.note_error}
          class="text-error text-sm [overflow-wrap:anywhere]"
          role="alert"
        >
          {note_error(@locale, @dialog.note_error)}
        </p>
        <textarea
          class="textarea textarea-bordered w-full"
          rows="2"
          name="note[body]"
          aria-label={t(@locale, "trips.notes.form.write_your_notes_for_this_day", %{})}
        ></textarea>
        <button type="submit" class="btn btn-sm">{t(@locale, "trips.notes.empty.save_note", %{})}</button>
      </form>
    </section>
    """
  end

  defp close, do: JS.push("visit:close") |> JS.pop_focus()
  defp v(locale, key), do: t(locale, "map.maplibre.visit_creation_modal." <> key, %{})
  defp e(locale, key), do: t(locale, "map.timeline_feeds.visit_entry." <> key, %{})

  defp message(_locale, error) when is_binary(error), do: error

  defp message(locale, _error),
    do: t(locale, "controllers.api.v1.settings.something_went_wrong", %{})

  defp note_error(_locale, {:invalid, errors}), do: Enum.join(errors, ", ")
  defp note_error(locale, reason), do: message(locale, reason)
end
