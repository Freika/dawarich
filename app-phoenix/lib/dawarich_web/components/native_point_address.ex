defmodule DawarichWeb.NativePointAddress do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.PointListFormat

  attr :address, :map, default: nil
  attr :locale, :string, required: true

  def drawer(%{address: nil} = assigns), do: ~H""

  def drawer(assigns) do
    assigns = assign(assigns, :text, PointListFormat.address(assigns.address, false))

    ~H"""
    <aside id="native-point-address" class="card bg-base-100 shadow p-3 min-w-0" role="status">
      <div class="flex flex-wrap items-start justify-between gap-2">
        <p :if={@text != ""} class="text-sm min-w-0 [overflow-wrap:anywhere]">
          <span class="font-semibold">{t(@locale, "points.address.address", %{})}</span> {@text}
        </p>
        <button type="button" class="btn btn-ghost btn-xs" phx-click="address:close" aria-label={t(@locale, "map.maplibre.area_creation_modal.cancel", %{})}>×</button>
      </div>
    </aside>
    """
  end
end
