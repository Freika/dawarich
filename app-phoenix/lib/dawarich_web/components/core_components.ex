defmodule DawarichWeb.CoreComponents do
  @moduledoc false
  use Phoenix.Component

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :class, :string, default: nil
  attr :options, :list, default: []
  attr :display, :string, default: nil
  attr :rest, :global, include: ~w(placeholder autocomplete min max step rows disabled required)

  def input(assigns) do
    errors = if used_input?(assigns.field), do: assigns.field.errors, else: []
    assign(assigns, :errors, Enum.map(errors, &translate_error/1)) |> field()
  end

  defp field(%{type: "checkbox"} = assigns) do
    assigns =
      assign(
        assigns,
        :checked,
        Phoenix.HTML.Form.normalize_value("checkbox", assigns.field.value)
      )

    ~H"""
    <div class="form-control">
      <label class="label cursor-pointer justify-start gap-4" for={@field.id}>
        <input type="hidden" name={@field.name} value="false" />
        <input
          type="checkbox"
          id={@field.id}
          name={@field.name}
          value="true"
          checked={@checked}
          class={@class || "toggle toggle-primary"}
          {@rest}
        />
        <span class="label-text font-medium">{@label}</span>
      </label>
      <.error :for={message <- @errors}>{message}</.error>
    </div>
    """
  end

  defp field(%{type: "select"} = assigns) do
    ~H"""
    <div class="form-control">
      <label class="label" for={@field.id}>{@label}</label>
      <select
        id={@field.id}
        name={@field.name}
        class={[@class || "select select-bordered w-full", @errors != [] && "select-error"]}
        aria-invalid={@errors != [] && "true"}
        {@rest}
      >
        {Phoenix.HTML.Form.options_for_select(@options, @field.value)}
      </select>
      <.error :for={message <- @errors}>{message}</.error>
    </div>
    """
  end

  defp field(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="form-control">
      <label class="label" for={@field.id}>{@label}</label>
      <textarea
        id={@field.id}
        name={@field.name}
        class={[@class || "textarea textarea-bordered w-full", @errors != [] && "textarea-error"]}
        aria-invalid={@errors != [] && "true"}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @field.value)}</textarea>
      <.error :for={message <- @errors}>{message}</.error>
    </div>
    """
  end

  defp field(assigns) do
    assigns =
      assign(
        assigns,
        :value,
        if(assigns.type == "password",
          do: assigns.display,
          else: Phoenix.HTML.Form.normalize_value(assigns.type, assigns.field.value)
        )
      )

    ~H"""
    <div class="form-control">
      <label class="label" for={@field.id}>{@label}</label>
      <input
        type={@type}
        name={@field.name}
        id={@field.id}
        value={@value}
        class={[@class || "input input-bordered w-full", @errors != [] && "input-error"]}
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
