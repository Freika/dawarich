defmodule DawarichWeb.NativeMapSettingsFields do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]

  @badge "badge badge-outline badge-warning badge-sm tooltip tooltip-left ml-auto mr-1 self-center"

  attr :fields, :list, default: nil
  attr :locale, :string, required: true

  def dirty_badge(assigns) do
    assigns = assign(assigns, :class, @badge)

    ~H"""
    <span
      :if={@fields in [nil, []]}
      class={@class <> " hidden"}
      data-dirty-badge
    ></span>
    <span
      :if={@fields not in [nil, []]}
      class={@class}
      data-dirty-badge
      data-tip={
        t(@locale, "javascript.settings.changed_fields", %{"fields" => Enum.join(@fields, ", ")})
      }
    >{t(@locale, "javascript.settings.unsaved_count", %{"count" => length(@fields)})}</span>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :unit, :string, required: true
  attr :hint, :string, required: true
  attr :value, :any, required: true
  attr :max, :string, default: nil

  def number(assigns) do
    ~H"""
    <div class="form-control w-full">
      <label class="label" for={@id}>
        <span class="label-text font-medium">{@label}</span>
      </label>
      <label class="input input-bordered flex items-center gap-2">
        <input
          type="number"
          id={@id}
          name={@name}
          aria-label={@label}
          min="1"
          max={@max}
          step="1"
          value={@value}
          required
          class="grow"
        />
        <span class="text-base-content/60">{@unit}</span>
      </label>
      <p class="text-xs text-base-content/60 mt-1">{@hint}</p>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :shown, :string, required: true
  attr :min, :string, required: true
  attr :max, :string, required: true
  attr :step, :string, required: true
  attr :value, :any, required: true
  attr :marks, :list, required: true
  attr :hint, :string, required: true

  def range(assigns) do
    ~H"""
    <div class="form-control w-full">
      <label class="label">
        <span class="label-text font-medium">{@label}</span>
        <span class="label-text-alt">{@shown}</span>
      </label>
      <input
        type="range"
        name={@name}
        aria-label={@label}
        min={@min}
        max={@max}
        step={@step}
        value={@value}
        class="range range-sm"
      />
      <div class="w-full flex justify-between text-xs px-2 mt-1">
        <span :for={mark <- @marks}>{mark}</span>
      </div>
      <p class="text-xs text-base-content/60 mt-1">{@hint}</p>
    </div>
    """
  end
end
