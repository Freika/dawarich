defmodule DawarichWeb.MapLive.Toast do
  @moduledoc false
  import Phoenix.LiveView, only: [push_event: 3]

  def push(socket, type, key, bindings \\ %{}) do
    push_event(socket, "map:toast", %{type: type, key: key, bindings: bindings})
  end
end
