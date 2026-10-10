defmodule DawarichWeb.RailsWidgets do
  @moduledoc false

  import Phoenix.LiveView, only: [put_flash: 3]

  def rails_flash(socket, %{"type" => type, "message" => message})
      when type in ["success", "error"] and is_binary(message),
      do: put_flash(socket, type, message)

  def rails_flash(socket, _params), do: socket
end
