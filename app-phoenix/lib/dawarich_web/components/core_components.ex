defmodule DawarichWeb.CoreComponents do
  @moduledoc false
  use Phoenix.Component

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :class, :string, default: "input input-bordered w-full"
  attr :rest, :global, include: ~w(placeholder autocomplete min max step)

  def input(assigns) do
    errors = if used_input?(assigns.field), do: assigns.field.errors, else: []
    assigns = assign(assigns, :errors, Enum.map(errors, &translate_error/1))

    ~H"""
    <div class="form-control">
      <label class="label" for={@field.id}>{@label}</label>
      <input
        type={@type}
        name={@field.name}
        id={@field.id}
        value={Phoenix.HTML.Form.normalize_value(@type, @field.value)}
        class={[@class, @errors != [] && "input-error"]}
        aria-invalid={@errors != [] && "true"}
        {@rest}
      />
      <.error :for={message <- @errors}>{message}</.error>
    </div>
    """
  end

  attr :class, :string, default: "btn btn-primary"
  attr :type, :string, default: "submit"
  attr :rest, :global, include: ~w(name value disabled form phx-disable-with)
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button type={@type} class={@class} {@rest}>{render_slot(@inner_block)}</button>
    """
  end

  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="label-text-alt text-error mt-1">{render_slot(@inner_block)}</p>
    """
  end

  defp translate_error({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
