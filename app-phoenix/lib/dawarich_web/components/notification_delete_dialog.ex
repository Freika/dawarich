defmodule DawarichWeb.NotificationDeleteDialog do
  @moduledoc false
  use DawarichWeb, :html
  alias Phoenix.LiveView.JS
  attr :locale, :string, required: true
  attr :target, :any, required: true
  attr :id, :string, required: true
  attr :title_id, :string, required: true
  attr :title, :string, required: true
  attr :cancel, :string, required: true
  attr :confirm, :string, required: true

  def dialog(assigns) do
    ~H"""
    <dialog
      id={@id}
      role="dialog"
      class="modal"
      open={@target != nil}
      phx-mounted={JS.ignore_attributes("open")}
      phx-window-keydown={@cancel}
      phx-key="Escape"
      aria-labelledby={@title_id}
    >
      <div class="modal-box min-w-0 [overflow-wrap:anywhere]">
        <h2 id={@title_id} class="text-lg font-bold">{@title}</h2>
        <div class="modal-action flex-wrap">
          <button
            type="button"
            class="btn h-auto whitespace-normal"
            phx-click={JS.push(@cancel) |> JS.dispatch("dawarich:close-dialog", to: "##{@id}")}
          >{t(@locale, "javascript.common.cancel", %{})}</button>
          <button
            type="button"
            class="btn btn-error h-auto whitespace-normal"
            phx-click={JS.push(@confirm) |> JS.dispatch("dawarich:close-dialog", to: "##{@id}")}
            phx-disable-with={t(@locale, "javascript.common.delete", %{})}
          >{t(@locale, "javascript.common.delete", %{})}</button>
        </div>
      </div>
      <button
        type="button"
        class="modal-backdrop"
        aria-label={t(@locale, "javascript.common.close", %{})}
        phx-click={JS.push(@cancel) |> JS.dispatch("dawarich:close-dialog", to: "##{@id}")}
      ></button>
    </dialog>
    """
  end
end
