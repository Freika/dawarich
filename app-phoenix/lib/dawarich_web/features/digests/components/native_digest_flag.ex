defmodule DawarichWeb.NativeDigestFlag do
  @moduledoc false
  use Phoenix.Component
  attr :name, :any, required: true
  attr :table, :list, required: true
  attr :id, :string, required: true
  attr :native, :boolean, default: true

  def flag(assigns) do
    svg =
      assigns
      |> DawarichWeb.Icon.country_flag()
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    svg = if assigns.native, do: namespace(svg, assigns.id), else: svg
    assigns = assign(assigns, :svg, Phoenix.HTML.raw(svg))

    ~H"""
    {@svg}
    """
  end

  defp namespace(svg, prefix) do
    identifiers =
      for [_, id] <- Regex.scan(~r/\sid="([^"]+)"/, svg), into: %{}, do: {id, prefix <> "-" <> id}

    svg =
      Enum.reduce(identifiers, svg, fn {id, scoped}, value ->
        value
        |> String.replace(~s(id="#{id}"), ~s(id="#{scoped}"))
        |> String.replace("url(##{id})", "url(##{scoped})")
        |> String.replace(~s(href="##{id}"), ~s(href="##{scoped}"))
      end)

    Regex.replace(~r/(aria-labelledby|aria-describedby)="([^"]+)"/, svg, fn _, key, value ->
      value = value |> String.split() |> Enum.map_join(" ", &Map.get(identifiers, &1, &1))
      ~s(#{key}="#{value}")
    end)
  end
end
