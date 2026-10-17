defmodule DawarichWeb.Chartkick do
  @moduledoc false
  use Phoenix.Component

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  attr :id, :string, required: true
  attr :data, :list, required: true
  attr :options, :list, required: true
  attr :height, :string, default: "300px"

  def column_chart(assigns) do
    assigns =
      assign(assigns,
        style:
          "height: #{assigns.height}; width: 100%; text-align: center; color: #999; line-height: #{assigns.height}; font-size: 14px; font-family: 'Lucida Grande', 'Lucida Sans Unicode', Verdana, Arial, Helvetica, sans-serif;",
        script: script("ColumnChart", assigns.id, assigns.data, assigns.options)
      )

    ~H"""
    <div id={@id} style={@style} phx-update="ignore">Loading...</div>
    {Phoenix.HTML.raw(@script)}
    """
  end

  def script(type, id, data, options) do
    create =
      "new Chartkick[#{json(type)}](#{json(id)}, #{json(data)}, #{json(ordered(options))});"

    """
    <script>
      (function() {
        if (document.documentElement.hasAttribute("data-turbolinks-preview")) return;
        if (document.documentElement.hasAttribute("data-turbo-preview")) return;

        var createChart = function() { #{create} };
        if ("Chartkick" in window) {
          createChart();
        } else {
          window.addEventListener("chartkick:load", createChart, true);
        }
      })();
    </script>
    """
  end

  defp json(value), do: value |> Ruby.json() |> IO.iodata_to_binary()

  defp ordered([{key, _} | _] = pairs) when is_atom(key),
    do: {:object, Enum.map(pairs, fn {k, v} -> {Atom.to_string(k), ordered(v)} end)}

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(value), do: value
end
