defmodule DawarichWeb.TripRecalculateStream do
  @moduledoc false
  use Phoenix.Component
  alias DawarichWeb.{Chrome, TripParts}

  def render(id, result, notice, locale) do
    stream(%{__changed__: nil, id: id, result: result, notice: notice, locale: locale})
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp stream(assigns) do
    ~H"""
    <turbo-stream :if={@result == :queued} action="replace" target="trip_recalculate_frame">
      <template><TripParts.recalculate_button
        trip_id={@id}
        recalculating={true}
        error={false}
        locale={@locale}
      /></template>
    </turbo-stream>
    <turbo-stream action="append" target="flash-messages">
      <template><Chrome.flash_message type="notice" message={@notice} locale={@locale} /></template>
    </turbo-stream>
    """
  end
end
