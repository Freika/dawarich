defmodule DawarichWeb.AuthorizedLiveChannel do
  @moduledoc false
  use GenServer, restart: :temporary

  alias Phoenix.LiveView.Channel

  def start_link({endpoint, from}) do
    timeout = endpoint.config(:live_view)[:hibernate_after] || 15000
    GenServer.start_link(__MODULE__, from, hibernate_after: timeout)
  end

  defdelegate init(from), to: Channel
  defdelegate handle_call(message, from, state), to: Channel
  defdelegate handle_cast(message, state), to: Channel
  defdelegate terminate(reason, state), to: Channel
  defdelegate code_change(old, state, extra), to: Channel
  defdelegate format_status(reason, state), to: Channel

  def handle_info(message, %{socket: %{assigns: %{admin_mode: _}} = socket} = state) do
    case DawarichWeb.AdminLiveAuth.authorize(socket) do
      {:cont, socket} -> Channel.handle_info(message, %{state | socket: socket})
      {:halt, socket} -> Channel.handle_info(:navbar_refresh, %{state | socket: socket})
    end
  end

  def handle_info(message, state), do: Channel.handle_info(message, state)
end
