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

  attr :rails, :boolean, default: false

  def chart(assigns) do
    if length(assigns.data) > 366 or
         assigns.kind not in ~w(ColumnChart BarChart LineChart AreaChart PieChart),
       do: raise(ArgumentError, "invalid chart")

    rows = rows(assigns.data)
    payload = Map.take(assigns, [:kind, :generation, :revision, :data, :options])

    assigns =
      assign(assigns,
        payload: Jason.encode!(payload),
        rows: rows,
        style:
          "height: #{assigns.height}; width: 100%; text-align: center; color: #999; line-height: #{assigns.height}; font-size: 14px; font-family: 'Lucida Grande', 'Lucida Sans Unicode', Verdana, Arial, Helvetica, sans-serif;"
      )

    ~H"""
    <div
      :if={@rails}
      id={@id}
      style={@style}
      phx-hook={unless @public, do: "NativeChart"}
      data-chart={@payload}
    >
      <div
        id={@id <> "-plot"}
        data-chart-plot
        phx-update={unless @public, do: "ignore"}
        style={"height: #{@height}; width: 100%"}
      >
      </div>
      <table class="sr-only">
        <caption>{@label}</caption><tbody>
          <tr :for={row <- @rows}>
            <td>{List.first(row)}</td><td>{List.last(row)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    <section
      :if={!@rails}
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

  def options([{key, _} | _] = values) when is_atom(key),
    do: Map.new(values, fn {key, value} -> {key, options(value)} end)

  def options(values) when is_list(values), do: Enum.map(values, &options/1)
  def options(value), do: value

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
