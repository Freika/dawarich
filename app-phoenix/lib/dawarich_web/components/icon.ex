defmodule DawarichWeb.Icon do
  @moduledoc false
  use Phoenix.Component

  @source Path.expand("../../../../app/assets/svg/icons", __DIR__)
  @root if File.dir?(@source), do: @source, else: Path.expand("../../../priv/svg_icons", __DIR__)

  for set <- ~w(lucide/outline brands),
      path <- [Path.join(@root, set) | Path.wildcard(Path.join([@root, set, "*.svg"]))],
      do: @external_resource(path)

  @outline Map.new(
             Path.wildcard(Path.join(@root, "lucide/outline/*.svg")),
             &{Path.basename(&1, ".svg"), File.read!(&1)}
           )
  @brands Map.new(
            Path.wildcard(Path.join(@root, "brands/*.svg")),
            &{Path.basename(&1, ".svg"), File.read!(&1)}
          )

  if @outline == %{} or @brands == %{}, do: raise("no SVG icons under #{@root}")

  attr :name, :string, required: true
  attr :class, :string, default: nil
  attr :id, :string, default: nil
  attr :aria_hidden, :boolean, default: false

  def icon(assigns) do
    assigns =
      assign(
        assigns,
        :svg,
        @outline
        |> Map.fetch!(Path.basename(assigns.name))
        |> String.replace(
          ~r/<svg[^>]*>/,
          svg_tag(assigns.class, assigns.aria_hidden, assigns[:id])
        )
        |> Phoenix.HTML.raw()
      )

    ~H"""
    {@svg}
    """
  end

  defp svg_tag(class, aria_hidden, id) do
    ~s(<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round") <>
      if(id, do: ~s( id="#{id}"), else: "") <>
      if(class, do: ~s( class="#{class}"), else: "") <>
      if(aria_hidden, do: ~s( aria-hidden="true"), else: "") <> ">"
  end

  attr :name, :string, required: true
  attr :class, :string, required: true

  def brand(assigns) do
    svg =
      @brands
      |> Map.fetch!(Path.basename(assigns.name))
      |> then(
        &Regex.replace(
          ~r/<svg([^>]*)>/,
          &1,
          fn _, attrs ->
            attrs = Regex.replace(~r/\sclass="[^"]*"/, attrs, "")
            ~s(<svg#{attrs} class="#{assigns.class}">)
          end,
          global: false
        )
      )

    assigns = assign(assigns, :svg, Phoenix.HTML.raw(svg))

    ~H"""
    {@svg}
    """
  end

  attr :code, :string, required: true
  attr :class, :string, default: "inline-block rounded-sm h-4 w-auto"
  attr :title, :string, default: nil

  def flag(assigns) do
    title =
      if assigns.title,
        do:
          ~s( title="#{assigns.title |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()}"),
        else: ""

    svg =
      assigns.code
      |> raw_flag_svg()
      |> then(
        &Regex.replace(
          ~r/<svg([^>]*)>/,
          &1,
          fn _, attrs -> ~s(<svg#{attrs} class="#{assigns.class}"#{title}>) end,
          global: false
        )
      )

    assigns = assign(assigns, :svg, Phoenix.HTML.raw(svg))

    ~H"""
    {@svg}
    """
  end

  defp raw_flag_svg(code) do
    case :persistent_term.get({__MODULE__, :flag, code}, nil) do
      nil ->
        svg =
          "app/assets/svg/icons/flags/landscape/#{Path.basename(code)}.svg"
          |> Dawarich.RailsRoot.join()
          |> File.read!()

        :persistent_term.put({__MODULE__, :flag, code}, svg)
        svg

      svg ->
        svg
    end
  end

  attr :name, :any, required: true
  attr :table, :list, required: true

  def country_flag(assigns) do
    assigns = assign(assigns, :code, Dawarich.CountryNames.flag_code(assigns.name, assigns.table))

    ~H"""
    <.flag :if={@code} code={@code} title={@name} />
    """
  end
end
