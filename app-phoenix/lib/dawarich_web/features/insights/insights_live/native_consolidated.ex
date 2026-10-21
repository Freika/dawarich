defmodule DawarichWeb.InsightsLive.NativeConsolidated do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.InsightsLive.{NativeMonths, NativeTracking, NativeYears}
  attr :data, :map, required: true
  attr :locale, :string, required: true

  def render(assigns) do
    ~H"""
    <%= if @data.all_time do %>
      <NativeTracking.render data={@data.consolidated} locale={@locale} />
      <NativeYears.render data={@data} locale={@locale} />
    <% else %>
      <NativeMonths.render data={@data} locale={@locale} />
    <% end %>
    """
  end
end
