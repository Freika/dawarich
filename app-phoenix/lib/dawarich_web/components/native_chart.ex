defmodule DawarichWeb.NativeChart do
  @moduledoc false
  use Phoenix.Component

  attr :id, :string, required: true
  attr :data, :list, required: true
  attr :options, :map, default: %{}
  attr :kind, :string, default: "ColumnChart"
  attr :generation, :integer, default: 0
  attr :revision, :string, required: true
  attr :label, :string, required: true
  attr :height, :string, default: "300px"
  attr :public, :boolean, default: false

  def chart(assigns) do
    if length(assigns.data) > 366 or
         assigns.kind not in ~w(ColumnChart BarChart LineChart AreaChart PieChart),
       do: raise(ArgumentError, "invalid chart")

    rows = rows(assigns.data)
    payload = Map.take(assigns, [:kind, :generation, :revision, :data, :options])
    assigns = assign(assigns, payload: Jason.encode!(payload), rows: rows)

    ~H"""
    <section
      id={@id}
      phx-hook={unless @public, do: "NativeChart"}
      data-chart={@payload}
      aria-label={@label}
      class="min-w-0 w-full"
    >
      <div
        id={@id <> "-plot"}
        data-chart-plot
        phx-update={unless @public, do: "ignore"}
        style={"height: #{@height}; width: 100%"}
      >
      </div>
      <details class="min-w-0">
        <summary class="break-words">{@label}</summary>
        <table class="table w-full">
          <tbody>
            <tr :for={row <- @rows}>
              <td class="break-words [overflow-wrap:anywhere]">{List.first(row)}</td><td>
                {List.last(row)}
              </td>
            </tr>
          </tbody>
        </table>
      </details>
    </section>
    """
  end

  defp rows(data) do
    Enum.flat_map(data, fn
      [label, value] -> [[label, value]]
      %{name: name, data: values} -> series(name, values)
      %{"name" => name, "data" => values} -> series(name, values)
      _ -> raise ArgumentError, "invalid chart"
    end)
  end

  defp series(name, values) when is_list(values) and length(values) <= 366,
    do: Enum.map(values, fn [label, value] -> ["#{name}: #{label}", value] end)

  defp series(_, _), do: raise(ArgumentError, "invalid chart")
end
