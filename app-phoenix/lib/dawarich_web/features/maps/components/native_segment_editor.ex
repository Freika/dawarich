defmodule DawarichWeb.NativeSegmentEditor do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

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
    <p
      :if={Map.get(@drawer, :notice) == :updated and is_nil(@drawer.error)}
      role="status"
      class="text-sm [overflow-wrap:anywhere]"
    >
      {t(@locale, "controllers.tracks.segments.segment_updated", %{})}
    </p>
    <p :if={@drawer.error} class="alert alert-error text-sm" role="alert">
      {error(@locale, @drawer.error)}
    </p>
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

  defp error(locale, code) when code in [:mode_not_enabled, :reprocess_failed],
    do: t(locale, "controllers.tracks.segments.#{code}", %{})

  defp error(locale, _code),
    do: t(locale, "controllers.tracks.segments.reprocess_failed", %{})
end
