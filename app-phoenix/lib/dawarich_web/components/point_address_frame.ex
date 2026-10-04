defmodule DawarichWeb.PointAddressFrame do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.PointListFormat

  attr :point, :map, required: true
  attr :locale, :string, required: true

  def frame(assigns) do
    assigns = assign(assigns, :address, PointListFormat.address(assigns.point, false))

    ~H"""
    <turbo-frame id={"point-address-#{@point.id}"}>
      <div :if={@address != ""}>
        <span class="font-semibold">{t(@locale, "points.address.address", %{})}</span> {@address}
      </div>
    </turbo-frame>
    """
  end
end
