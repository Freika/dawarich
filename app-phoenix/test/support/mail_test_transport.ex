defmodule Dawarich.Mail.TestTransport do
  @moduledoc false

  def deliver(message, _env) do
    send(self(), {:mail, message})

    if watcher = Process.get(:hang_in_transport) do
      send(watcher, {:in_transport, message})
      Process.sleep(:infinity)
    end

    if Process.get(:crash_after_send), do: raise("crashed after the server accepted the message")
    Process.get(:transport_result, :ok)
  end
end
