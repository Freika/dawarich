defmodule DawarichWeb.AdminLive.Instance do
  @moduledoc false
  use DawarichWeb, :live_view

  alias Dawarich.Admin.{Instance, InstancePage}
  alias DawarichWeb.{AdminInstance, AdminUI, SettingsParts}

  @timeout 10_000
  @tests %{"test_geocoding" => :geocoding, "test_map_matching" => :map_matching}
  @crash_errors %{geocoding: "Geocoding::Error", map_matching: "connection_failed"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: t(socket.assigns.locale, "admin.settings.show.title", %{}),
       two_factor: SettingsParts.two_factor_available?(),
       saves: 0,
       testing: MapSet.new(),
       timers: %{},
       data: nil,
       section: nil,
       health: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, %{assigns: %{data: nil}} = socket),
    do: {:noreply, load(socket, params["section"])}

  def handle_params(params, _uri, socket),
    do:
      {:noreply,
       assign(socket, :section, InstancePage.section(socket.assigns.data, params["section"]))}

  @impl true
  def handle_event("save", params, socket) do
    socket.assigns.current_scope
    |> Instance.save(params, opts())
    |> saved(socket)
  rescue
    _ -> {:noreply, alert(socket, "controllers.application.admin_action_failed")}
  end

  def handle_event(event, _params, socket) when is_map_key(@tests, event) do
    name = Map.fetch!(@tests, event)

    if MapSet.member?(socket.assigns.testing, name) do
      {:noreply, socket}
    else
      scope = socket.assigns.current_scope
      opts = opts()
      token = make_ref()
      timer = Process.send_after(self(), {:admin_async_timeout, name, token}, @timeout)

      {:noreply,
       socket
       |> update(:testing, &MapSet.put(&1, name))
       |> update(:timers, &Map.put(&1, name, {token, timer}))
       |> start_async(name, fn -> run(name, scope, opts) end)}
    end
  end

  def handle_event(_event, _params, socket),
    do: {:noreply, AdminUI.refuse(socket, :invalid_input)}

  @impl true
  def handle_async(name, result, socket) do
    if MapSet.member?(socket.assigns.testing, name) do
      socket = finish(socket, name)

      case result do
        {:ok, outcome} -> {:noreply, tested(socket, name, outcome)}
        {:exit, _} -> {:noreply, failed(socket, name, Map.fetch!(@crash_errors, name))}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:admin_async_timeout, name, token}, socket) do
    case socket.assigns.timers do
      %{^name => {^token, _timer}} ->
        {:noreply, socket |> cancel_async(name) |> finish(name) |> failed(name, "timeout")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns), do: AdminInstance.show(assigns)

  defp finish(socket, name) do
    {{_token, timer}, timers} = Map.pop(socket.assigns.timers, name)
    Process.cancel_timer(timer)
    assign(socket, testing: MapSet.delete(socket.assigns.testing, name), timers: timers)
  end

  defp load(socket, section) do
    case Instance.page(socket.assigns.current_scope, section, opts()) do
      {:ok, page} -> assign(socket, data: page.data, section: page.section, health: page.health)
      {:error, reason} -> refuse(socket, reason)
    end
  end

  defp reload(socket),
    do: socket |> update(:saves, &(&1 + 1)) |> load(socket.assigns.section)

  defp saved({:ok, :saved}, socket),
    do: {:noreply, socket |> reload() |> notice("admin.settings.update.saved")}

  defp saved({:ok, {:pinned, variables}}, socket),
    do:
      {:noreply,
       socket
       |> reload()
       |> put_flash(
         :alert,
         t(socket.assigns.locale, "admin.settings.update.pinned", %{
           variables: Enum.join(variables, ", ")
         })
       )}

  defp saved({:error, {:invalid, message}}, socket),
    do: {:noreply, put_flash(socket, :alert, message)}

  defp saved({:error, reason}, socket), do: {:noreply, refuse(socket, reason)}

  defp tested(socket, _name, {kind, message})
       when kind in [:notice, :alert] and is_binary(message),
       do: put_flash(socket, kind, message)

  defp tested(socket, _name, {kind, key, bindings}) when kind in [:notice, :alert],
    do: put_flash(socket, kind, t(socket.assigns.locale, key, bindings))

  defp tested(socket, _name, {:error, reason}), do: refuse(socket, reason)

  defp failed(socket, :geocoding, error),
    do:
      put_flash(
        socket,
        :alert,
        t(socket.assigns.locale, "admin.settings.test_geocoding.failure", %{error: error})
      )

  defp failed(socket, :map_matching, error),
    do:
      put_flash(
        socket,
        :alert,
        t(socket.assigns.locale, "admin.settings.test_map_matching.failure", %{error: error})
      )

  defp run(:geocoding, scope, opts), do: Instance.test_geocoding(scope, opts)
  defp run(:map_matching, scope, opts), do: Instance.test_map_matching(scope, opts)

  defp refuse(socket, reason), do: AdminUI.refuse(socket, reason)

  defp notice(socket, key), do: put_flash(socket, :notice, t(socket.assigns.locale, key, %{}))
  defp alert(socket, key), do: put_flash(socket, :alert, t(socket.assigns.locale, key, %{}))

  defp opts, do: Application.get_env(:dawarich, :admin_instance_opts, [])
end
