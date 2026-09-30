defmodule DawarichWeb.Icon do
  @moduledoc false
  use Phoenix.Component

  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(assigns) do
    name = Path.basename(assigns.name)
    path = Dawarich.RailsRoot.join("app/assets/svg/icons/lucide/outline/#{name}.svg")

    assigns =
      assign(
        assigns,
        :svg,
        path
        |> File.read!()
        |> String.replace(~r/<svg[^>]*>/, svg_tag(assigns.class))
        |> Phoenix.HTML.raw()
      )

    ~H"""
    {@svg}
    """
  end

  defp svg_tag(nil),
    do:
      ~s(<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">)

  defp svg_tag(class),
    do:
      ~s(<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class="#{class}">)

  attr :name, :string, required: true
  attr :class, :string, required: true

  def brand(assigns) do
    svg =
      "app/assets/svg/icons/brands/#{Path.basename(assigns.name)}.svg"
      |> Dawarich.RailsRoot.join()
      |> File.read!()
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
