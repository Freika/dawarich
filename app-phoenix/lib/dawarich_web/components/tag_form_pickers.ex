defmodule DawarichWeb.TagFormPickers do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @colors ~w(#ef4444 #f97316 #f59e0b #eab308 #84cc16 #22c55e #10b981 #14b8a6 #06b6d4 #0ea5e9 #3b82f6 #6366f1 #8b5cf6 #a855f7 #d946ef #ec4899 #f43f5e #64748b)

  attr :locale, :string, required: true
  attr :tag, :map, required: true
  attr :emoji, :string, required: true

  def pickers(assigns) do
    icon =
      if Ruby.blank?(assigns.tag.icon),
        do: if(assigns.tag.id, do: "🏠", else: assigns.emoji),
        else: assigns.tag.icon

    color = if Ruby.blank?(assigns.tag.color), do: "#6ab0a4", else: assigns.tag.color
    assigns = assign(assigns, icon: icon, color: color, colors: @colors)

    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
      <div
        class="form-control"
        data-controller="emoji-picker"
        data-emoji-picker-auto-submit-value="false"
      >
        <label class="label" for="tag_icon">Icon</label>
        <div class="relative w-full">
          <button
            type="button"
            class="input input-bordered w-full flex items-center justify-center text-4xl cursor-pointer hover:bg-base-200 min-h-[4rem]"
            data-action="click->emoji-picker#toggle"
            data-emoji-picker-target="button"
            data-default-icon={@icon}
          ><span data-emoji-picker-display>{@icon}</span></button>
          <div data-emoji-picker-target="pickerContainer" class="hidden absolute z-50 mt-2 left-0">
          </div>
          <input
            value={@icon}
            data-emoji-picker-target="input"
            type="hidden"
            name="tag[icon]"
            id="tag_icon"
          />
        </div>
        <label class="label"><span class="label-text-alt">{t(
          @locale,
          "tags.form.click_to_select_an_emoji",
          %{}
        )}</span></label>
      </div>
      <div
        class="form-control"
        data-controller="color-picker"
        data-color-picker-default-value={@color}
      >
        <label class="label" for="tag_color">Color</label>
        <div class="flex flex-col gap-3">
          <div class="grid grid-cols-6 gap-2">
            <button
              :for={color <- @colors}
              type="button"
              class="w-10 h-10 rounded-lg cursor-pointer transition-all hover:scale-110 border-2 border-base-300"
              style={"background-color: #{color};"}
              data-color={color}
              data-color-picker-target="swatch"
              data-action="click->color-picker#selectSwatch"
              title={color}
            ></button>
          </div>
          <div class="flex flex-wrap items-center gap-3">
            <label class="flex items-center gap-2 cursor-pointer group min-w-0"><span class="text-sm font-medium">{t(
              @locale,
              "tags.form.custom",
              %{}
            )}</span><input
              type="color"
              class="w-12 h-12 rounded-lg cursor-pointer border-2 border-base-300 hover:scale-105 transition-transform color-input"
              value={@color}
              data-color-picker-target="picker"
              data-action="input->color-picker#updateFromPicker"
            /></label>
            <div class="flex-1 min-w-0 flex items-center gap-2">
              <div
                class="w-8 h-8 rounded border-2 border-base-300"
                data-color-picker-target="display"
                style={"background-color: #{@color};"}
              >
              </div><span class="text-sm text-base-content/60" data-color-picker-target="displayText">{@color}</span>
            </div>
          </div>
        </div>
        <input
          value={@color}
          data-color-picker-target="input"
          type="hidden"
          name="tag[color]"
          id="tag_color"
        />
        <label class="label"><span class="label-text-alt">{t(
          @locale,
          "tags.form.choose_from_swatches_or_pick_a_custom_color",
          %{}
        )}</span></label>
      </div>
    </div>
    """
  end
end
