defmodule DawarichWeb.InsightsFrameAuth do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [detach_hook: 3]

  def on_mount(:default, params, session, socket) do
    case DawarichWeb.LiveAuth.on_mount(:default, params, session, socket) do
      {:cont, socket} ->
        frame = session["insights_frame"] == true
        socket = assign(socket, :insights_frame, frame)

        if frame do
          {:cont,
           socket
           |> detach_hook(:navbar_params, :handle_params)
           |> detach_hook(:navbar_info, :handle_info)
           |> detach_hook(:navbar_event, :handle_event)}
        else
          {:cont, socket}
        end

      halted ->
        halted
    end
  end
end
