defmodule DawarichWeb.Cable.Socket do
  @moduledoc false
  @behaviour WebSock

  alias Dawarich.Cable.{Bus, Channels, Frames}

  @impl WebSock
  def init(%{identity: :unauthorized} = state),
    do: {:stop, :normal, 1000, [{:text, Frames.disconnect("unauthorized", false)}], state}

  def init(%{identity: :silent} = state), do: {:ok, state}

  def init(%{identity: {:ok, identity}} = state) do
    {:ok, _} = :timer.send_interval(state.beat_ms, :beat)
    {:push, [{:text, Frames.welcome()}], %{state | identity: identity}}
  end

  @impl WebSock
  def handle_in({text, opcode: :text}, %{identity: %{}} = state) do
    case Jason.decode(text) do
      {:ok, %{"command" => "subscribe", "identifier" => id}} when is_binary(id) ->
        subscribe(id, state)

      {:ok, %{"command" => "unsubscribe", "identifier" => id}} when is_binary(id) ->
        unsubscribe(id, state)

      _ ->
        {:ok, state}
    end
  end

  def handle_in(_frame, state), do: {:ok, state}

  @impl WebSock
  def handle_info(:beat, state),
    do: {:push, [{:text, Frames.ping(System.os_time(:second))}], state}

  def handle_info(message, %{identity: %{}} = state) do
    case Bus.event(message) do
      {:subscribed, broadcasting} -> confirm(broadcasting, state)
      {:message, broadcasting, payload} -> deliver(broadcasting, payload, state)
      :ignore -> {:ok, state}
    end
  end

  def handle_info(_message, state), do: {:ok, state}

  @impl WebSock
  def terminate(_reason, _state), do: :ok

  defp subscribe(id, state) when is_map_key(state.subs, id), do: {:ok, state}

  defp subscribe(id, state) do
    case Jason.decode(id) do
      {:ok, %{} = params} ->
        decide(Channels.authorize(params, state.identity, state.context), id, state)

      _ ->
        {:ok, state}
    end
  end

  defp decide({:stream, broadcasting}, id, state) do
    {:ok, _ref} = Bus.subscribe(broadcasting)
    {:ok, put_in(state.subs[id], {broadcasting, :pending})}
  end

  defp decide(:confirm, id, state),
    do: {:push, [{:text, Frames.confirm(id)}], put_in(state.subs[id], nil)}

  defp decide(:reject, id, state), do: {:push, [{:text, Frames.reject(id)}], state}
  defp decide(:ignore, _id, state), do: {:ok, state}

  defp unsubscribe(id, state) when not is_map_key(state.subs, id), do: {:ok, state}

  defp unsubscribe(id, state) do
    {sub, subs} = Map.pop(state.subs, id)

    with {broadcasting, _} <- sub,
         false <- Enum.any?(subs, &match?({_, {^broadcasting, _}}, &1)),
         do: Bus.unsubscribe(broadcasting)

    {:ok, %{state | subs: subs}}
  end

  defp confirm(broadcasting, state) do
    ids = for {id, {^broadcasting, :pending}} <- state.subs, do: id
    subs = Enum.reduce(ids, state.subs, &Map.put(&2, &1, {broadcasting, :confirmed}))
    reply(for(id <- ids, do: {:text, Frames.confirm(id)}), %{state | subs: subs})
  end

  defp deliver(broadcasting, payload, state),
    do:
      reply(
        for(
          {id, {^broadcasting, :confirmed}} <- state.subs,
          do: {:text, Frames.message(id, payload)}
        ),
        state
      )

  defp reply([], state), do: {:ok, state}
  defp reply(frames, state), do: {:push, frames, state}
end
