defmodule DawarichWeb.IntegrationBrand do
  @moduledoc false

  def svg(name, css, prefix) do
    svg =
      DawarichWeb.Icon.brand(%{__changed__: nil, name: name, class: css})
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    Regex.scan(~r/\bid="([^"]+)"/, svg, capture: :all_but_first)
    |> List.flatten()
    |> Enum.reduce(svg, fn id, svg ->
      svg
      |> String.replace(~s(id="#{id}"), ~s(id="#{prefix}-#{id}"))
      |> String.replace("url(##{id})", "url(##{prefix}-#{id})")
      |> String.replace("url('##{id}')", "url('##{prefix}-#{id}')")
      |> String.replace(~s|url("##{id}")|, ~s|url("##{prefix}-#{id}")|)
      |> String.replace(~s(href="##{id}"), ~s(href="##{prefix}-#{id}"))
    end)
    |> Phoenix.HTML.raw()
  end
end
