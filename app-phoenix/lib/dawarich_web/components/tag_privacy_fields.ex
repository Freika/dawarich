defmodule DawarichWeb.TagPrivacyFields do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  alias DawarichWeb.TagErrors

  attr :locale, :string, required: true
  attr :radius, :integer, default: nil
  attr :errors, :list, default: []

  def fields(assigns) do
    ~H"""
    <div data-controller="privacy-radius">
      <div class="form-control">
        <label class="label cursor-pointer"><span class="label-text font-semibold"><.icon
          name="lock-open"
          class="inline-block w-4"
        /> {t(@locale, "tags.form.privacy_zone", %{})}</span><input
          type="checkbox"
          class="toggle toggle-error"
          data-privacy-radius-target="toggle"
          data-action="change->privacy-radius#toggleRadius"
          checked={not is_nil(@radius)}
        /></label>
        <label class="label"><span class="label-text-alt">{t(
          @locale,
          "tags.form.hide_map_data_around_places_with_this_tag",
          %{}
        )}</span></label>
      </div>
      <div
        class={if is_nil(@radius), do: "form-control hidden", else: "form-control"}
        data-privacy-radius-target="radiusInput"
      >
        <TagErrors.field field="privacy_radius_meters" errors={@errors}>
          <label class="label" for="tag_privacy_radius_meters">{t(
            @locale,
            "tags.form.privacy_radius",
            %{}
          )}</label>
        </TagErrors.field>
        <div class="flex flex-col gap-2">
          <input
            type="range"
            min="50"
            max="5000"
            step="50"
            value={@radius || 1000}
            class="range range-error"
            data-privacy-radius-target="slider"
            data-action="input->privacy-radius#updateFromSlider"
          />
          <div class="flex justify-between text-xs px-2">
            <span>{t(@locale, "units.meters_compact", %{value: 50})}</span><span
              class="font-semibold"
              data-privacy-radius-target="label"
            >{@radius || 1000}m</span><span>{t(@locale, "units.meters_compact", %{value: 5000})}</span>
          </div>
          <input
            value={@radius}
            data-privacy-radius-target="field"
            type="hidden"
            name="tag[privacy_radius_meters]"
            id="tag_privacy_radius_meters"
          />
        </div>
        <label class="label"><span class="label-text-alt">{t(
          @locale,
          "tags.form.data_within_this_radius_will_be_hidden_from_the_map",
          %{}
        )}</span></label>
      </div>
    </div>
    """
  end
end
