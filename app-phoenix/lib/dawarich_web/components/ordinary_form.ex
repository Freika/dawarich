defmodule DawarichWeb.OrdinaryFormComponents do
  @moduledoc false
  use Phoenix.Component
  alias Phoenix.LiveView.JS

  attr :state, :any, required: true

  def summary(assigns) do
    messages =
      if assigns.state.changeset.action in [:insert, :update, :create],
        do:
          Enum.map(assigns.state.changeset.errors, fn {_, {message, _}} -> message end)
          |> Enum.uniq(),
        else: []

    assigns = assign(assigns, :messages, messages)

    ~H"""
    <ul :if={@messages != []} role="alert" class="text-error [overflow-wrap:anywhere]">
      <li :for={message <- @messages}>{message}</li>
    </ul>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :cancel_event, :string, required: true
  attr :close_label, :string, required: true
  slot :inner_block, required: true

  def dialog(assigns) do
    ~H"""
    <dialog
      id={@id}
      aria-labelledby={@id <> "-title"}
      class="modal"
      phx-mounted={JS.dispatch("dawarich:open-dialog")}
      phx-remove={JS.dispatch("dawarich:close-dialog")}
      phx-window-keydown={
        JS.push(@cancel_event) |> JS.dispatch("dawarich:close-dialog", to: "#" <> @id)
      }
      phx-key="Escape"
    >
      <div class="modal-box min-w-0 [overflow-wrap:anywhere]">
        <h2 id={@id <> "-title"} class="text-xl font-bold">{@title}</h2>
        {render_slot(@inner_block)}
        <button
          type="button"
          class="btn mt-3"
          phx-click={JS.push(@cancel_event) |> JS.dispatch("dawarich:close-dialog", to: "#" <> @id)}
        >{@close_label}</button>
      </div>
      <button
        type="button"
        class="modal-backdrop"
        aria-label={@close_label}
        phx-click={JS.push(@cancel_event) |> JS.dispatch("dawarich:close-dialog", to: "#" <> @id)}
      ></button>
    </dialog>
    """
  end
end
