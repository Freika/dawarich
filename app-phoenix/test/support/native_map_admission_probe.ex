defmodule Dawarich.Test.NativeMapAdmissionProbe do
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.MapLiveAuth, :default}

  def mount(_, _, socket), do: {:ok, assign(socket, :accepted, 0)}

  def render(assigns) do
    ~H"""
    <output id="accepted">{@accepted}</output>
    """
  end

  def handle_event("command", _, socket), do: {:noreply, update(socket, :accepted, &(&1 + 1))}

  def handle_event("begin", _, socket) do
    owner = Application.fetch_env!(:dawarich, :native_map_probe_owner)

    {:noreply,
     start_async(socket, :probe, fn ->
       send(owner, {:map_probe_task, self()})
       receive do: (:release -> :accepted)
     end)}
  end

  def handle_params(params, _, socket) do
    if params["probe"],
      do: {:noreply, update(socket, :accepted, &(&1 + 1))},
      else: {:noreply, socket}
  end

  def handle_async(:probe, {:ok, :accepted}, socket),
    do: {:noreply, update(socket, :accepted, &(&1 + 1))}

  def handle_info(:late_result, socket), do: {:noreply, update(socket, :accepted, &(&1 + 1))}
end

defmodule Dawarich.Test.NativeMapProbeRouter do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :probe do
    plug DawarichWeb.RailsAuth
    plug :fetch_live_flash
  end

  scope "/" do
    pipe_through :probe

    live_session :map_probe, session: {DawarichWeb.MapLiveAuth, :live_session, []} do
      live "/", Dawarich.Test.NativeMapAdmissionProbe
    end
  end
end
