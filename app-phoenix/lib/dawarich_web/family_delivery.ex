defmodule DawarichWeb.FamilyDelivery do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, push_event: 3]
  alias Dawarich.Families

  def attach(socket) do
    if connected?(socket), do: Families.subscribe_changes(socket.assigns.current_scope)

    socket
    |> assign(locations: [], family_expiry: nil)
    |> attach_hook(:family_delivery_params, :handle_params, fn _, _, s -> {:cont, reload(s)} end)
    |> attach_hook(:family_delivery_event, :handle_event, &event/3)
    |> attach_hook(:family_delivery_info, :handle_info, &info/2)
  end

  def reload(socket) do
    cancel(socket.assigns[:family_expiry])

    if connected?(socket) and socket.assigns.page.state == :show do
      case Families.locations(socket.assigns.current_scope) do
        {:ok, snapshot} ->
          socket
          |> assign(locations: snapshot.locations, family_expiry: schedule(snapshot.deadline))
          |> push_event("family-locations", %{locations: snapshot.locations})

        _ ->
          clear(socket)
      end
    else
      assign(socket, locations: [], family_expiry: deadline(socket))
    end
  end

  defp deadline(socket) do
    if connected?(socket) do
      case Families.deadline(socket.assigns.current_scope) do
        {:ok, due} -> schedule(due)
        _ -> nil
      end
    end
  end

  defp schedule(%NaiveDateTime{} = due) do
    token = make_ref()
    delay = max(1, NaiveDateTime.diff(due, NaiveDateTime.utc_now(), :millisecond))
    timer = Process.send_after(self(), {:family_expiry, token}, min(delay, 4_294_967_295))
    %{token: token, timer: timer, due: due}
  end

  defp schedule(_), do: nil

  defp event("family_reload", _, socket), do: {:halt, reload(socket)}

  defp event("family_focus", %{"id" => id}, socket) when is_binary(id) do
    socket = reload(socket)

    case Enum.find(socket.assigns.locations, &(to_string(&1["user_id"]) == id)) do
      nil -> {:halt, socket}
      row -> {:halt, push_event(socket, "family-focus", %{id: row["user_id"]})}
    end
  end

  defp event(_, _, socket), do: {:cont, socket}

  defp info({:domain_changed, id, _}, %{assigns: %{current_user: %{id: id}}} = socket),
    do: {:halt, reload(socket)}

  defp info({:family_expiry, token}, %{assigns: %{family_expiry: %{token: token}}} = socket),
    do: {:halt, reload(socket)}

  defp info({:family_expiry, _}, socket), do: {:halt, socket}
  defp info(_, socket), do: {:cont, socket}

  def clear(socket) do
    cancel(socket.assigns[:family_expiry])

    socket
    |> assign(page: nil, locations: [], history: nil, confirmation: nil, family_expiry: nil)
    |> push_event("family-clear", %{})
  end

  defp cancel(%{timer: timer}), do: Process.cancel_timer(timer)
  defp cancel(_), do: :ok
end
