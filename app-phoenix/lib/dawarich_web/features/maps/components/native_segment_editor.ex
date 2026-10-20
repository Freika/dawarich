defmodule DawarichWeb.NativeSegmentEditor do
  @moduledoc false
  use Phoenix.Component

  attr :drawer, :map, default: nil
  attr :locale, :string, required: true
  attr :unit, :string, default: "km"
  attr :now, :any, default: nil

  def drawer(%{drawer: nil} = assigns), do: ~H""

  def drawer(assigns) do
    assigns =
      assign(assigns, :mode_user, %{
        settings: %{"enabled_transportation_modes" => assigns.drawer.modes}
      })

    ~H"""
    <DawarichWeb.SegmentFrame.frame
      track_id={@drawer.track_id}
      segments={@drawer.segments}
      user={@mode_user}
      locale={@locale}
      csrf=""
      unit={@unit}
      now={@now || DateTime.utc_now()}
      native
    />
    """
  end
end
