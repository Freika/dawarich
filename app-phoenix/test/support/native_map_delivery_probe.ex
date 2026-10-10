defmodule Dawarich.Test.NativeMapDeliveryProbe do
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.MapLiveAuth, :default}
  alias DawarichWeb.MapLive.Subscriptions

  def mount(_, _, socket),
    do:
      {:ok,
       Subscriptions.sync(socket, %{kind: :map, scope: socket.assigns.current_scope},
         bus: Dawarich.Test.NativeMapBus
       )}

  def render(assigns), do: ~H"<output id=\"native-delivery\">ready</output>"

  def handle_info(message, socket) do
    {_, socket} = Subscriptions.deliver(socket, message)
    {:noreply, socket}
  end
end

defmodule Dawarich.Test.NativeMapDeliveryRouter do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :delivery do
    plug DawarichWeb.RailsAuth
    plug :fetch_live_flash
  end

  scope "/" do
    pipe_through :delivery

    live_session :map_delivery, session: {DawarichWeb.MapLiveAuth, :live_session, []} do
      live "/", Dawarich.Test.NativeMapDeliveryProbe
    end
  end
end
