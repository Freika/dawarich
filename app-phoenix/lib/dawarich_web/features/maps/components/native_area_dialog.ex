defmodule DawarichWeb.NativeAreaDialog do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias Phoenix.LiveView.JS

  attr :dialog, :map, default: nil
  attr :locale, :string, required: true

  def dialog(%{dialog: nil} = assigns), do: ~H""

  def dialog(assigns) do
    assigns = assign(assigns, :radius, assigns.dialog.form["radius"])

    ~H"""
    <div>
      <div
        id="native-area-dialog"
        phx-hook="AreaPreview"
        class="modal z-[10000] modal-open"
        role="dialog"
        aria-modal="true"
        phx-mounted={JS.focus_first(to: "#native-area-form")}
        phx-window-keydown={close()}
        phx-key="escape"
      >
        <div class="modal-box max-w-xl">
          <h3 class="font-bold text-lg mb-4">
            {if @dialog.id, do: js(@locale, "edit"), else: a(@locale, "create_new_area")}
          </h3>
          <ul :if={@dialog.errors != []} class="alert alert-error mb-4 block" role="alert">
            <li :for={error <- @dialog.errors} class="[overflow-wrap:anywhere]">{error}</li>
          </ul>
          <form
            id="native-area-form"
            phx-submit="area:save"
            action="/areas"
            accept-charset="UTF-8"
            method="post"
          >
            <input type="hidden" name="latitude" id="latitude" value={@dialog.form["latitude"]} />
            <input
              type="hidden"
              name="longitude"
              id="longitude"
              value={@dialog.form["longitude"]}
            />

            <div class="space-y-4">
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">{a(@locale, "area_name")}</span>
                </label>
                <input
                  placeholder={a(@locale, "e_g_home_office_gym")}
                  aria-label={a(@locale, "area_name")}
                  class="input input-bordered w-full"
                  required
                  type="text"
                  name="name"
                  id="name"
                  value={@dialog.form["name"]}
                />
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">{a(@locale, "radius")}</span>
                  <span class="label-text-alt">
                    <span>{@radius || "0"}</span> {a(@locale, "meters")}
                  </span>
                </label>
                <input
                  min="10"
                  placeholder={a(@locale, "radius_in_meters")}
                  aria-label={a(@locale, "radius")}
                  class="input input-bordered w-full"
                  required
                  type="number"
                  name="radius"
                  id="radius"
                  value={@radius}
                />
              </div>
            </div>

            <div class="modal-action">
              <button
                :if={@dialog.id}
                id="native-area-delete"
                type="button"
                class="btn btn-error btn-outline mr-auto"
                phx-click="area:delete"
                phx-value-id={@dialog.id}
                data-confirm={t(@locale, "javascript.areas.confirm_delete", %{})}
              >
                {t(@locale, "javascript.common.delete", %{})}
              </button>
              <button type="button" class="btn btn-ghost" phx-click={close()}>
                {a(@locale, "cancel")}
              </button>
              <input
                type="submit"
                name="commit"
                value={if @dialog.id, do: js(@locale, "update"), else: a(@locale, "create_area")}
                class="btn btn-primary"
                phx-disable-with={a(@locale, "creating")}
              />
            </div>
          </form>
        </div>
        <div class="modal-backdrop" phx-click={close()}></div>
      </div>
    </div>
    """
  end

  defp close, do: JS.push("area:close") |> JS.pop_focus()
  defp a(locale, key), do: t(locale, "map.maplibre.area_creation_modal." <> key, %{})
  defp js(locale, key), do: t(locale, "javascript.areas." <> key, %{})
end
