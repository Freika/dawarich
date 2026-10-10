defmodule DawarichWeb.PlaceForm do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.CoreComponents
  alias DawarichWeb.OrdinaryFormComponents, as: Ordinary
  attr :state, :any, required: true
  attr :data, :map, required: true
  attr :locale, :string, required: true
  attr :nearby, :any, default: nil

  def form(assigns) do
    assigns =
      assign(assigns, :form, to_form(assigns.state.changeset, as: :place, id: assigns.state.id))

    ~H"""
    <Ordinary.dialog
      id={@state.id <> "-dialog"}
      title={
        if @data.id, do: t(@locale, "places.drawer.edit", %{}), else: p(@locale, "create_new_place")
      }
      cancel_event="cancel_form"
      close_label={p(@locale, "cancel")}
    >
      <p
        :if={@state.status == :uncertain}
        data-uncertain-save
        role="alert"
        class="text-error [overflow-wrap:anywhere]"
      >
        {DawarichWeb.PlacesUI.uncertain_message(@locale)}
      </p>
      <button :if={@state.status == :uncertain} type="button" class="btn" phx-click="check_places">
        {t(@locale, "places.index.places", %{})}
      </button>
      <p :if={@state.status == :partial} role="alert" class="text-error [overflow-wrap:anywhere]">
        {DawarichWeb.PlacesUI.message(@locale)}
      </p>
      <button :if={@state.status == :partial} type="button" class="btn" phx-click="recover_place">{t(
        @locale,
        "javascript.messages.retry",
        %{}
      )}</button>
      <form
        id={@state.id}
        phx-change="validate_place"
        phx-submit="save_place"
        data-form-status={@state.status}
        data-place-id={@data.id || ""}
      >
        <input type="hidden" name="generation" value={@state.generation} />
        <Ordinary.summary state={@state} />
        <.input field={@form[:name]} label={p(@locale, "place_name")} required />
        <.input
          field={@form[:latitude]}
          label={t(@locale, "javascript.map_info.latitude", %{})}
          inputmode="decimal"
          required
        />
        <.input
          field={@form[:longitude]}
          label={t(@locale, "javascript.map_info.longitude", %{})}
          inputmode="decimal"
          required
        />
        <.input field={@form[:note]} label={p(@locale, "note")} type="textarea" rows="3" />
        <fieldset class="my-3 min-w-0">
          <legend>{p(@locale, "tags")}</legend>
          <input type="hidden" name="place[tag_ids][]" value="" />
          <div class="flex flex-wrap gap-3 min-w-0">
            <label
              :for={tag <- @data.tags}
              for={@state.id <> "-tag-#{tag.id}"}
              class="flex gap-2 min-w-0 [overflow-wrap:anywhere]"
            >
              <input
                id={@state.id <> "-tag-#{tag.id}"}
                type="checkbox"
                class="checkbox"
                name="place[tag_ids][]"
                value={tag.id}
                checked={to_string(tag.id) in (@form[:tag_ids].value || [])}
              />{tag.icon} {tag.name}
            </label>
          </div>
        </fieldset>
        <button
          type="submit"
          class="btn btn-primary"
          disabled={@state.status != :idle}
          phx-disable-with={p(@locale, "saving")}
        >{if @data.id, do: t(@locale, "places.drawer.save", %{}), else: p(@locale, "create_place")}</button>
      </form>
      <section class="mt-4" data-nearby-state={if @nearby, do: @nearby.status, else: :idle}>
        <h3 class="font-semibold">{p(@locale, "nearby_places")}</h3>
        <p :if={@nearby && @nearby.status == :loading} role="status">
          {t(@locale, "javascript.common.loading", %{})}
        </p>
        <p :if={@nearby && @nearby.status == :empty}>
          {t(@locale, "places.nearby_places.no_nearby_places_found", %{})}
        </p>
        <p :if={@nearby && @nearby.error} role="alert" class="text-error [overflow-wrap:anywhere]">
          {@nearby.error}
        </p>
        <button
          type="button"
          class="btn btn-sm"
          phx-click="nearby"
          phx-value-generation={@state.generation}
          disabled={@state.status != :idle || (@nearby && @nearby.status == :loading)}
        >{t(@locale, "javascript.messages.retry", %{})}</button>
        <button
          :if={@nearby && @nearby.status in [:results, :empty] && @nearby.radius < 1.5}
          type="button"
          class="btn btn-sm"
          phx-click="nearby"
          phx-value-generation={@state.generation}
          phx-value-radius={to_string(@nearby.radius + 0.5)}
        >{t(@locale, "places.nearby_places.load_more_search_up_to_distance_m", %{
          distance: round((@nearby.radius + 0.5) * 1000)
        })}</button>
        <div class="flex flex-col gap-2">
          <button
            :for={result <- if(@nearby, do: @nearby.results, else: [])}
            type="button"
            class="btn h-auto min-w-0 flex-wrap [overflow-wrap:anywhere]"
            phx-click="select_nearby"
            phx-value-generation={@state.generation}
            phx-value-run={@nearby.run_id}
            phx-value-index={result.index}
          >{result.name}</button>
        </div>
      </section>
    </Ordinary.dialog>
    """
  end

  defp p(locale, key), do: t(locale, "shared.place_creation_modal." <> key, %{})
end
