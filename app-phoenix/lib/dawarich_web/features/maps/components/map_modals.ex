defmodule DawarichWeb.MapModals do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  attr :page, :map, required: true
  attr :locale, :string, required: true

  def visit_creation_modal(assigns) do
    ~H"""
    <div
      data-controller="visit-creation-v2"
      data-visit-creation-v2-api-key-value={@page.api_key}
      data-visit-creation-v2-timezone-value={@page.timezone}
    >
      <div class="modal z-[10000]" data-visit-creation-v2-target="modal">
        <div class="modal-box max-w-2xl">
          <h3 class="font-bold text-lg mb-4" data-visit-creation-v2-target="modalTitle">
            {v(@locale, "create_new_visit")}
          </h3>

          <form data-visit-creation-v2-target="form" data-action="submit->visit-creation-v2#submit">
            <input type="hidden" name="latitude" data-visit-creation-v2-target="latitudeInput" />
            <input type="hidden" name="longitude" data-visit-creation-v2-target="longitudeInput" />

            <div class="space-y-4">
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">{v(@locale, "visit_name")}</span>
                </label>
                <input
                  type="text"
                  name="name"
                  placeholder={v(@locale, "enter_visit_name")}
                  class="input input-bordered w-full"
                  data-visit-creation-v2-target="nameInput"
                  required
                />
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">{v(@locale, "start_time")}</span>
                  </label>
                  <input
                    type="datetime-local"
                    name="started_at"
                    max="9999-12-31T23:59"
                    class="input input-bordered w-full"
                    data-visit-creation-v2-target="startTimeInput"
                    required
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">{v(@locale, "end_time")}</span>
                  </label>
                  <input
                    type="datetime-local"
                    name="ended_at"
                    max="9999-12-31T23:59"
                    class="input input-bordered w-full"
                    data-visit-creation-v2-target="endTimeInput"
                    required
                  />
                </div>
              </div>
            </div>

            <div class="modal-action">
              <button type="button" class="btn btn-ghost" data-action="click->visit-creation-v2#close">{v(
                @locale,
                "cancel"
              )}</button>
              <button
                type="submit"
                class="btn btn-primary"
                data-visit-creation-v2-target="submitButton"
              >{v(@locale, "create_visit")}</button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop" data-action="click->visit-creation-v2#close"></div>
      </div>
    </div>
    """
  end

  defp v(locale, key), do: t(locale, "map.maplibre.visit_creation_modal." <> key, %{})

  attr :locale, :string, required: true
  attr :rails_csrf_token, :string, required: true

  def area_creation_modal(assigns) do
    ~H"""
    <div data-controller="area-creation-v2">
      <div class="modal z-[10000]" data-area-creation-v2-target="modal">
        <div class="modal-box max-w-xl">
          <h3 class="font-bold text-lg mb-4" data-area-creation-v2-target="modalTitle">
            {a(@locale, "create_new_area")}
          </h3>

          <form
            data-area-creation-v2-target="form"
            data-action="turbo:submit-end->area-creation-v2#onSubmitEnd"
            action="/areas"
            accept-charset="UTF-8"
            method="post"
          >
            <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
            <input
              data-area-creation-v2-target="latitudeInput"
              type="hidden"
              name="latitude"
              id="latitude"
            />
            <input
              data-area-creation-v2-target="longitudeInput"
              type="hidden"
              name="longitude"
              id="longitude"
            />

            <div class="space-y-4">
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">{a(@locale, "area_name")}</span>
                </label>
                <input
                  placeholder={a(@locale, "e_g_home_office_gym")}
                  class="input input-bordered w-full"
                  data-area-creation-v2-target="nameInput"
                  required="required"
                  type="text"
                  name="name"
                  id="name"
                />
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">{a(@locale, "radius")}</span>
                  <span class="label-text-alt">
                    <span data-area-creation-v2-target="radiusDisplay">0</span> {a(@locale, "meters")}
                  </span>
                </label>
                <input
                  min="10"
                  placeholder={a(@locale, "radius_in_meters")}
                  class="input input-bordered w-full"
                  data-area-creation-v2-target="radiusInput"
                  data-action="input->area-creation-v2#updateRadiusDisplay"
                  required="required"
                  type="number"
                  name="radius"
                  id="radius"
                />
              </div>
            </div>

            <div class="modal-action">
              <button type="button" class="btn btn-ghost" data-action="click->area-creation-v2#close">{a(
                @locale,
                "cancel"
              )}</button>
              <input
                type="submit"
                name="commit"
                value={a(@locale, "create_area")}
                class="btn btn-primary"
                data-area-creation-v2-target="submitButton"
                data-disable-with={a(@locale, "creating")}
              />
            </div>
          </form>
        </div>
        <div class="modal-backdrop" data-action="click->area-creation-v2#close"></div>
      </div>
    </div>
    """
  end

  defp a(locale, key), do: t(locale, "map.maplibre.area_creation_modal." <> key, %{})
end
