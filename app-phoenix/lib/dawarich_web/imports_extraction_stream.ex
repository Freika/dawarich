defmodule DawarichWeb.ImportsExtractionStream do
  @moduledoc false
  use Phoenix.Component

  def render(record, locale, csrf, now) do
    replace(%{__changed__: nil, record: record, locale: locale, csrf: csrf, now: now})
    |> Phoenix.HTML.Safe.to_iodata()
  end

  defp replace(assigns) do
    ~H"""
    <turbo-stream action="replace" target={"import-#{@record.id}-extraction"}>
      <template>
        <DawarichWeb.ImportsExtractionCard.card
          record={@record}
          locale={@locale}
          csrf={@csrf}
          now={@now}
        />
      </template>
    </turbo-stream>
    """
  end
end
