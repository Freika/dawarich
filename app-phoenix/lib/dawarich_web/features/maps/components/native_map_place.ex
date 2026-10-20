defmodule DawarichWeb.NativeMapPlace do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias Phoenix.LiveView.JS

  attr :dialog, :map, default: nil
  attr :locale, :string, required: true

  def dialog(%{dialog: nil} = assigns), do: ~H""

  def dialog(assigns) do
    ~H"""
    <div>
      <div
        id="native-place-dialog"
        phx-hook="OrdinaryDialog"
        class="modal z-[10000] modal-open"
        role="dialog"
        aria-modal="true"
        phx-window-keydown={close()}
        phx-key="escape"
      >
        <div class="modal-box max-w-2xl">
          <h3 class="font-bold text-lg mb-4">
            {if @dialog.id,
              do: t(@locale, "javascript.places.edit", %{}),
              else: p(@locale, "create_new_place")}
          </h3>
          <ul :if={@dialog.errors != []} class="alert alert-error mb-4 block" role="alert">
            <li :for={error <- @dialog.errors} class="[overflow-wrap:anywhere]">
              {message(@locale, error)}
            </li>
          </ul>
          <form
            id="native-place-form"
            phx-change="place:change"
            phx-submit="place:save"
            action="/places"
            accept-charset="UTF-8"
            method="post"
          >
            <input
              type="hidden"
              name="place[latitude]"
              id="place_latitude"
              value={@dialog.form["latitude"]}
            />
            <input
              type="hidden"
              name="place[longitude]"
              id="place_longitude"
              value={@dialog.form["longitude"]}
            />
            <input value="manual" type="hidden" name="place[source]" id="place_source" />
            <input type="hidden" name="_method_url" />

            <div class="space-y-4">
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">{p(@locale, "place_name")}</span>
                </label>
                <input
                  placeholder={p(@locale, "enter_place_name")}
                  aria-label={p(@locale, "place_name")}
                  class="input input-bordered w-full"
                  required
                  type="text"
                  name="place[name]"
                  id="place_name"
                  data-native-dialog-initial-focus
                  value={@dialog.form["name"]}
                />
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">{p(@locale, "note")}</span>
                </label>
                <textarea
                  placeholder={p(@locale, "add_a_personal_note_about_this_place")}
                  aria-label={p(@locale, "note")}
                  class="textarea textarea-bordered w-full bg-base-100"
                  rows="3"
                  name="place[note]"
                  id="place_note"
                >{@dialog.form["note"]}</textarea>
                <label class="label">
                  <span class="label-text-alt">
                    {p(@locale, "optional_add_any_notes_or_details_about_this_place")}
                  </span>
                </label>
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">{p(@locale, "tags")}</span>
                </label>
                <div class="flex flex-wrap gap-2">
                  <label :for={tag <- @dialog[:tags] || []} class="cursor-pointer">
                    <input
                      type="checkbox"
                      name="place[tag_ids][]"
                      value={tag.id}
                      class="checkbox checkbox-sm hidden peer"
                      aria-label={tag.name}
                      checked={to_string(tag.id) in List.wrap(@dialog.form["tag_ids"])}
                    />
                    <span
                      class="badge badge-lg badge-outline transition-all peer-checked:scale-105"
                      style={color(tag.color)}
                      data-color={tag.color}
                    >
                      {tag.icon} #{tag.name}
                    </span>
                  </label>
                </div>
                <label class="label">
                  <span class="label-text-alt">
                    {p(@locale, "click_tags_to_select_them_for_this_place")}
                  </span>
                </label>
              </div>

              <div class="divider">{p(@locale, "suggested_places")}</div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">{p(@locale, "nearby_places")}</span>
                </label>
                <div class="relative">
                  <p :if={is_nil(@dialog[:nearby])} class="text-sm text-gray-500">
                    {p(@locale, "open_modal_to_load_nearby_suggestions")}
                  </p>
                  <DawarichWeb.NearbyPlaces.render
                    :if={@dialog[:nearby]}
                    places={@dialog.nearby}
                    radius={@dialog[:nearby_radius] || 0.5}
                    params={%{}}
                    locale={@locale}
                    native
                  />
                </div>
              </div>
            </div>

            <div class="modal-action">
              <button type="button" class="btn btn-ghost" phx-click={close()}>
                {p(@locale, "cancel")}
              </button>
              <input
                type="submit"
                name="commit"
                value={
                  if @dialog.id,
                    do: t(@locale, "javascript.places.update", %{}),
                    else: p(@locale, "create_place")
                }
                class="btn btn-primary"
                phx-disable-with={p(@locale, "saving")}
              />
            </div>
          </form>
        </div>
        <div class="modal-backdrop" phx-click={close()}></div>
      </div>

      <div id="place-creation-data" class="hidden"></div>
    </div>
    """
  end

  defp close, do: JS.push("place:close") |> JS.pop_focus()

  defp color(value) when is_binary(value) do
    if value =~ ~r/\A#[0-9a-fA-F]{3,8}\z/, do: "border-color: #{value}; color: #{value};"
  end

  defp color(_value), do: nil
  defp p(locale, key), do: t(locale, "shared.place_creation_modal." <> key, %{})
  defp message(_locale, error) when is_binary(error), do: error

  defp message(locale, _error),
    do: t(locale, "controllers.api.v1.settings.something_went_wrong", %{})
end
