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
end
