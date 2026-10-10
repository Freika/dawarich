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
    <div
      id="native-place-dialog"
      class="modal modal-open z-[10000]"
      role="dialog"
      aria-modal="true"
      phx-mounted={JS.focus_first(to: "#native-place-form")}
      phx-window-keydown={close()}
      phx-key="escape"
    >
      <div class="modal-box min-w-0">
        <h3 class="font-bold text-lg mb-4 break-words">
          {t(
            @locale,
            if(@dialog.id, do: "javascript.places.edit", else: "javascript.places.create_new"),
            %{}
          )}
        </h3>
        <ul :if={@dialog.errors != []} class="alert alert-error mb-4 block" role="alert">
          <li :for={error <- @dialog.errors} class="[overflow-wrap:anywhere]">
            {message(@locale, error)}
          </li>
        </ul>
        <form id="native-place-form" phx-submit="place:save" class="space-y-3">
          <input type="hidden" name="place[latitude]" value={@dialog.form["latitude"]} />
          <input type="hidden" name="place[longitude]" value={@dialog.form["longitude"]} />
          <label class="form-control">
            <span class="label-text font-semibold">{t(
              @locale,
              "shared.place_creation_modal.place_name",
              %{}
            )}</span>
            <input
              class="input input-bordered w-full"
              type="text"
              name="place[name]"
              value={@dialog.form["name"]}
            />
          </label>
          <ul :if={@dialog.nearby != []} class="menu bg-base-200 rounded-box">
            <li :for={place <- @dialog.nearby}>
              <span class="[overflow-wrap:anywhere]">{place["name"]}</span>
            </li>
          </ul>
          <div class="modal-action flex-wrap gap-2">
            <button type="button" class="btn btn-ghost" phx-click={close()}>
              {t(@locale, "map.maplibre.area_creation_modal.cancel", %{})}
            </button>
            <button type="submit" class="btn btn-primary">{t(
              @locale,
              if(@dialog.id, do: "javascript.places.update", else: "javascript.places.create"),
              %{}
            )}</button>
          </div>
        </form>
      </div>
      <div class="modal-backdrop" phx-click={close()}></div>
    </div>
    """
  end

  defp close, do: JS.push("place:close") |> JS.pop_focus()
  defp message(_locale, error) when is_binary(error), do: error

  defp message(locale, _error),
    do: t(locale, "controllers.api.v1.settings.something_went_wrong", %{})
end
