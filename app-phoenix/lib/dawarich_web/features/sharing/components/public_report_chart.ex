defmodule DawarichWeb.PublicReportChart do
  @moduledoc false
  use Phoenix.Component

  attr :id, :string, default: "chart-1"
  attr :data, :list, required: true
  attr :options, :map, required: true
  attr :revision, :string, required: true
  attr :height, :string, default: "200px"

  def chart(assigns) do
    if length(assigns.data) > 366, do: raise(ArgumentError, "invalid chart")

    payload = %{
      kind: "ColumnChart",
      generation: 0,
      revision: assigns.revision,
      data: assigns.data,
      options: options(assigns.options)
    }

    assigns =
      assign(assigns,
        payload: Jason.encode!(payload),
        style:
          "height: #{assigns.height}; width: 100%; text-align: center; color: #999; line-height: #{assigns.height}; font-size: 14px; font-family: 'Lucida Grande', 'Lucida Sans Unicode', Verdana, Arial, Helvetica, sans-serif;"
      )

    ~H"""
    <div id={@id} style={@style} data-chart={@payload} data-chart-plot>Loading...</div>
    """
  end

  defp options(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, options(item)} end)

  defp options(value) when is_list(value) do
    if Keyword.keyword?(value),
      do: Map.new(value, fn {key, item} -> {key, options(item)} end),
      else: Enum.map(value, &options/1)
  end

  defp options(value), do: value
end
