defmodule DawarichWeb.MapPlaceModal do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :rails_csrf_token, :string, required: true

  def place_creation_modal(assigns) do
    ~H"""
    <div data-controller="place-creation">
      <div class="modal z-[10000]" data-place-creation-target="modal">
        <div class="modal-box max-w-2xl">
          <h3 class="font-bold text-lg mb-4" data-place-creation-target="modalTitle">
            {p(@locale, "create_new_place")}
          </h3>

          <form
            data-place-creation-target="form"
            data-action="turbo:submit-end->place-creation#onSubmitEnd"
            action="/places"
            accept-charset="UTF-8"
            method="post"
          >
            <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
            <input
              data-place-creation-target="latitudeInput"
              type="hidden"
              name="place[latitude]"
              id="place_latitude"
            />
            <input
              data-place-creation-target="longitudeInput"
              type="hidden"
              name="place[longitude]"
              id="place_longitude"
            />
            <input value="manual" type="hidden" name="place[source]" id="place_source" />
            <input type="hidden" name="_method_url" data-place-creation-target="placeIdInput" />

            <div class="space-y-4">
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">{p(@locale, "place_name")}</span>
                </label>
                <input
                  placeholder={p(@locale, "enter_place_name")}
                  class="input input-bordered w-full"
                  data-place-creation-target="nameInput"
                  required="required"
                  type="text"
                  name="place[name]"
                  id="place_name"
                />
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">{p(@locale, "note")}</span>
                </label>
                <textarea
                  placeholder={p(@locale, "add_a_personal_note_about_this_place")}
                  class="textarea textarea-bordered w-full bg-base-100"
                  rows="3"
                  data-place-creation-target="noteInput"
                  name="place[note]"
                  id="place_note"
                ></textarea>
                <label class="label">
                  <span class="label-text-alt">{p(
                    @locale,
                    "optional_add_any_notes_or_details_about_this_place"
                  )}</span>
                </label>
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">{p(@locale, "tags")}</span>
                </label>
                <div class="flex flex-wrap gap-2" data-place-creation-target="tagCheckboxes">
                  <label :for={tag <- @page.tags} class="cursor-pointer">
                    <input
                      type="checkbox"
                      name="place[tag_ids][]"
                      value={tag.id}
                      class="checkbox checkbox-sm hidden peer"
                    />
                    <span
                      class="badge badge-lg badge-outline transition-all peer-checked:scale-105"
                      style={"border-color: #{tag.color}; color: #{tag.color};"}
                      data-color={to_string(tag.color)}
                    >{tag.icon} #{tag.name}</span>
                  </label>
                </div>
                <label class="label">
                  <span class="label-text-alt">{p(@locale, "click_tags_to_select_them_for_this_place")}</span>
                </label>
              </div>

              <div class="divider">{p(@locale, "suggested_places")}</div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">{p(@locale, "nearby_places")}</span>
                </label>
                <div class="relative">
                  <turbo-frame id="nearby-places" data-place-creation-target="nearbyFrame">
                    <p class="text-sm text-gray-500">
                      {p(@locale, "open_modal_to_load_nearby_suggestions")}
                    </p>
                  </turbo-frame>
                </div>
              </div>
            </div>

            <div class="modal-action">
              <button type="button" class="btn btn-ghost" data-action="click->place-creation#close">{p(
                @locale,
                "cancel"
              )}</button>
              <input
                type="submit"
                name="commit"
                value={p(@locale, "create_place")}
                class="btn btn-primary"
                data-place-creation-target="submitButton"
                data-disable-with={p(@locale, "saving")}
              />
            </div>
          </form>
        </div>
        <div class="modal-backdrop" data-action="click->place-creation#close"></div>
      </div>

      <div id="place-creation-data" class="hidden"></div>
    </div>
    """
  end

  defp p(locale, key), do: t(locale, "shared.place_creation_modal." <> key, %{})
end
