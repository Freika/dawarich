defmodule DawarichWeb.ErrorHTML do
  @moduledoc false

  def render(template, _assigns) do
    case File.read(Dawarich.RailsRoot.join("public/" <> template)) do
      {:ok, html} -> Phoenix.HTML.raw(html)
      {:error, _reason} -> Phoenix.Controller.status_message_from_template(template)
    end
  end
end
