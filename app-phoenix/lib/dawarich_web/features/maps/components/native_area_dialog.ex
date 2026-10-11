defmodule DawarichWeb.NativeAreaDialog do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias Phoenix.LiveView.JS

  attr :dialog, :map, default: nil
  attr :locale, :string, required: true

  def dialog(%{dialog: nil} = assigns), do: ~H""

  def dialog(assigns) do
    ~H"""
    <div
      id="native-area-dialog"
      phx-hook="AreaPreview"
      class="modal modal-open z-[10000]"
      role="dialog"
      aria-modal="true"
      aria-labelledby="native-area-title"
      phx-mounted={JS.focus_first(to: "#native-area-form")}
      phx-window-keydown={close()}
      phx-key="escape"
    >
      <div class="modal-box min-w-0">
        <h3 id="native-area-title" class="font-bold text-lg mb-4 break-words">
          {js(@locale, if(@dialog.id, do: "edit", else: "create_new"))}
        </h3>
        <ul :if={@dialog.errors != []} class="alert alert-error mb-4 block" role="alert">
          <li :for={error <- @dialog.errors} class="[overflow-wrap:anywhere]">{error}</li>
        </ul>
        <form id="native-area-form" phx-submit="area:save" class="space-y-4">
          <input type="hidden" name="area[latitude]" value={@dialog.form["latitude"]} />
          <input type="hidden" name="area[longitude]" value={@dialog.form["longitude"]} />
          <label class="form-control">
            <span class="label-text font-semibold">{a(@locale, "area_name")}</span>
            <input
              class="input input-bordered w-full"
              type="text"
              name="area[name]"
              value={@dialog.form["name"]}
              placeholder={a(@locale, "e_g_home_office_gym")}
              required
            />
          </label>
          <label class="form-control">
            <span class="label-text font-semibold">
              {a(@locale, "radius")} ({a(@locale, "meters")})
            </span>
            <input
              class="input input-bordered w-full"
              type="text"
              inputmode="numeric"
              name="area[radius]"
              value={@dialog.form["radius"]}
              placeholder={a(@locale, "radius_in_meters")}
              required
            />
          </label>
          <div class="modal-action flex-wrap gap-2">
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
            <button type="submit" class="btn btn-primary" phx-disable-with={a(@locale, "creating")}>
              {js(@locale, if(@dialog.id, do: "update", else: "create"))}
            </button>
          </div>
        </form>
      </div>
      <div class="modal-backdrop" phx-click={close()}></div>
    </div>
    """
  end

  defp close, do: JS.push("area:close") |> JS.pop_focus()
  defp a(locale, key), do: t(locale, "map.maplibre.area_creation_modal." <> key, %{})
  defp js(locale, key), do: t(locale, "javascript.areas." <> key, %{})
end
