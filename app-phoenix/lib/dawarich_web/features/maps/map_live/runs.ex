defmodule DawarichWeb.MapLive.Runs do
  @moduledoc false
  import Phoenix.LiveView, only: [cancel_async: 2, start_async: 3]

  def start(socket, name, previous, fun, timeout) do
    run = make_ref()
    socket = if previous, do: cancel_async(socket, {name, previous}), else: socket
    {run, start_async(socket, {name, run}, fn -> Dawarich.BoundedTask.run(fun, timeout) end)}
  end
end
