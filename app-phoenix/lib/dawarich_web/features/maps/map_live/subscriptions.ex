defmodule DawarichWeb.MapLive.Subscriptions do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, push_event: 3]
  alias Dawarich.Maps.Realtime

  def sync(socket, descriptor, opts \\ []) do
    state =
      socket.assigns[:native_subscriptions] ||
        %{
          descriptor: descriptor,
          topics: %{},
          bus: Keyword.get(opts, :bus, Dawarich.Maps.EventBus),
          opts: Keyword.take(opts, [:now, :self_hosted]),
          seen: [],
          revision: 0,
          ttl: Keyword.get(opts, :admission_ttl_ms, ttl(descriptor.kind)),
          admitted: nil
        }

    socket = assign(socket, :native_subscriptions, %{state | descriptor: descriptor})

    if connected?(socket) do
      case admit(socket) do
        {:ok, socket, desired} -> reconcile(socket, desired)
        {:error, reason} -> refuse(socket, reason)
      end
    else
      release(socket)
    end
  end

  def release(socket) do
    case socket.assigns[:native_subscriptions] do
      nil ->
        socket

      state ->
        Enum.each(state.topics, fn {topic, ref} -> state.bus.unsubscribe(topic, ref) end)
        assign(socket, :native_subscriptions, %{state | topics: %{}})
    end
  end

  def deliver(socket, message) do
    state = socket.assigns[:native_subscriptions]

    case state && state.bus.event(message) do
      {:message, topic, payload} when is_binary(payload) ->
        if Map.has_key?(state.topics, topic),
          do: admit_message(socket, topic, payload),
          else: {:ignored, socket}

      {:domain_message, topic} ->
        if Map.has_key?(state.topics, topic),
          do: admit_message(socket, topic, nil),
          else: {:ignored, socket}

      {:subscribed, topic} ->
        if Map.has_key?(state.topics, topic),
          do: {:delivered, reconnect(socket)},
          else: {:ignored, socket}

      _ ->
        {:ignored, socket}
    end
  end

  def reconnect(socket) do
    state = socket.assigns[:native_subscriptions]

    case state && admit(socket) do
      {:ok, socket, desired} -> socket |> reconcile(desired) |> invalidate("reconnect")
      {:error, reason} -> refuse(socket, reason)
      _ -> socket
    end
  end

  defp admit_message(socket, topic, payload) do
    state = socket.assigns.native_subscriptions

    case admitted(socket, topic) do
      {:ok, socket, desired} ->
        fingerprint = if is_binary(payload), do: :crypto.hash(:sha256, topic <> payload)

        cond do
          not Map.has_key?(desired, topic) ->
            {:ignored, socket}

          fingerprint && fingerprint in state.seen ->
            {:ignored, socket}

          true ->
            updated = %{
              socket.assigns.native_subscriptions
              | seen:
                  if(fingerprint, do: Enum.take([fingerprint | state.seen], 32), else: state.seen)
            }

            {:delivered,
             socket |> assign(:native_subscriptions, updated) |> invalidate(desired[topic])}
        end

      {:error, reason} ->
        {:refused, refuse(socket, reason)}
    end
  end

  defp ttl(:map), do: 5_000
  defp ttl(_kind), do: 0

  defp admitted(socket, topic) do
    case socket.assigns.native_subscriptions do
      %{ttl: ttl, admitted: {at, desired}} when ttl > 0 ->
        if now() - at < ttl and not String.starts_with?(topic, ["family:", "sharing:"]),
          do: {:ok, socket, desired},
          else: readmit(socket)

      _ ->
        readmit(socket)
    end
  end

  defp readmit(socket) do
    with {:ok, socket, desired} <- admit(socket), do: {:ok, reconcile(socket, desired), desired}
  end

  defp admit(socket) do
    state = socket.assigns.native_subscriptions

    with {:ok, desired} <- Realtime.topics(state.descriptor, state.opts) do
      state = %{state | admitted: {now(), desired}}
      {:ok, assign(socket, :native_subscriptions, state), desired}
    end
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp reconcile(socket, desired) do
    state = socket.assigns.native_subscriptions

    removed = Map.keys(state.topics) -- Map.keys(desired)

    Enum.each(removed, fn topic ->
      state.bus.unsubscribe(topic, state.topics[topic])
    end)

    topics = Map.take(state.topics, Map.keys(desired))

    topics =
      Enum.reduce(Map.keys(desired) -- Map.keys(topics), topics, fn topic, acc ->
        case subscribe(state.bus, topic) do
          {:ok, ref} -> Map.put(acc, topic, ref)
          _ -> acc
        end
      end)

    socket = assign(socket, :native_subscriptions, %{state | topics: topics})

    if state.descriptor.kind == :map and removed != [],
      do: invalidate(socket, "reconnect"),
      else: socket
  end

  defp subscribe(bus, topic) do
    bus.subscribe(topic)
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp invalidate(socket, kind) do
    state = socket.assigns.native_subscriptions
    revision = state.revision + 1

    socket
    |> assign(:native_subscriptions, %{state | revision: revision})
    |> push_event("map:invalidate", %{kind: kind, revision: revision})
  end

  defp refuse(socket, reason),
    do: socket |> release() |> push_event("map:clear", %{code: Atom.to_string(reason)})
end
