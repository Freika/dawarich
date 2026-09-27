defmodule DawarichWeb.ErrorHTML do
  @moduledoc false

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
