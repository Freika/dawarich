defmodule DawarichWeb.PublicMapDeadline do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1]

  def cancel(socket) do
    if active = socket.assigns[:public_deadline], do: Process.cancel_timer(active.timer)
    assign(socket, :public_deadline, nil)
  end

  def schedule(socket) do
    config = socket.assigns[:public_config]

    if connected?(socket) && config && config["validUntil"] do
      key = {config["validUntil"], config["revision"]}

      if socket.assigns[:public_deadline] && socket.assigns.public_deadline.key == key do
        socket
      else
        socket = cancel(socket)
        {:ok, expiry, _} = DateTime.from_iso8601(config["validUntil"])

        delay =
          DateTime.diff(expiry, DateTime.utc_now(), :millisecond) |> max(0) |> min(86_400_000)

        token = make_ref()
        timer = Process.send_after(self(), {:public_map_expiry, token}, delay)
        assign(socket, :public_deadline, %{timer: timer, token: token, key: key})
      end
    else
      cancel(socket)
    end
  end

  def receive_expiry(socket, token) do
    case socket.assigns[:public_deadline] do
      %{token: ^token} -> socket |> cancel() |> schedule()
      _ -> socket
    end
  end
end
