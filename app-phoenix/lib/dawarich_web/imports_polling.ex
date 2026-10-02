defmodule DawarichWeb.ImportsPolling do
  @moduledoc false

  @active_statuses [0, 1, 4, "created", "processing", "deleting"]
  @active_extraction [1, 2, "pending", "running"]

  def schedule(socket, imports) do
    if Phoenix.LiveView.connected?(socket) and not socket.assigns.polling and
         Enum.any?(imports, &active?/1) do
      Process.send_after(
        self(),
        :imports_refresh,
        Application.get_env(:dawarich, :imports_poll_ms, 1000)
      )

      Phoenix.Component.assign(socket, :polling, true)
    else
      socket
    end
  end

  def active?(import) do
    Map.get(import, :status) in @active_statuses or
      Map.get(import, :additional_data_extraction_status, Map.get(import, :extraction)) in @active_extraction
  end
end
