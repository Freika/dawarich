defmodule DawarichWeb.AdmissionMemoHook do
  @moduledoc false
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, detach_hook: 3]

  alias Dawarich.Accounts.DataAccess

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) and not DataAccess.memo_open?() do
      DataAccess.open_memo()
      {:cont, attach_hook(socket, __MODULE__, :after_render, &close/1)}
    else
      {:cont, socket}
    end
  end

  defp close(socket) do
    DataAccess.close_memo()
    detach_hook(socket, __MODULE__, :after_render)
  end
end
