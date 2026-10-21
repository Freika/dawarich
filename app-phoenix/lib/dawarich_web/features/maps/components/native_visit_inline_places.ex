defmodule DawarichWeb.NativeVisitInlinePlaces do
  @moduledoc false
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :editing, :map, required: true
  attr :locale, :string, required: true

  def places(assigns) do
    ~H"""
    <div :if={@editing.places != []} class="flex flex-wrap gap-2">
      <button
        :for={place <- @editing.places}
        type="button"
        class={[
          "btn btn-xs",
          if(place.id == @editing.place_id, do: "btn-primary", else: "btn-outline")
        ]}
        phx-click={JS.push("visit:place", value: %{place_id: to_string(place.id)})}
      >
        <span class="[overflow-wrap:anywhere]">{place.name}</span>
      </button>
    </div>
    <DawarichWeb.NativeVisitPlaceSearch.search search={@editing[:search]} locale={@locale} />
    """
  end
end
