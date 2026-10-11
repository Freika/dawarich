defmodule DawarichWeb.ImportsStallTimer do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]

  def now(socket), do: (socket.assigns[:imports_clock] || (&DateTime.utc_now/0)).()

  def schedule(socket, records) do
    socket = cancel(socket)

    if Phoenix.LiveView.connected?(socket) do
      case Dawarich.Imports.StallDeadlines.nearest(records, socket.assigns.now) do
        nil ->
          socket

        at ->
          token = make_ref()
          delay = max(1, DateTime.diff(at, socket.assigns.now, :millisecond))
          timer = Process.send_after(self(), {:import_stall_deadline, token}, delay)
          assign(socket, :import_stall_timer, %{timer: timer, token: token, at: at})
      end
    else
      socket
    end
  end

  def current?(socket, token), do: match?(%{token: ^token}, socket.assigns[:import_stall_timer])

  def cancel(socket) do
    if timer = socket.assigns[:import_stall_timer] do
      if timer.timer, do: Process.cancel_timer(timer.timer)
    end

    assign(socket, :import_stall_timer, nil)
  end
end
