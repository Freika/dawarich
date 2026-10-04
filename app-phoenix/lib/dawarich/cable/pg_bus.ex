defmodule Dawarich.Cable.PgBus do
  @moduledoc false
  use GenServer

  alias Dawarich.Cable.{Bus, PgStore}

  def child_spec(opts) do
    child = %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

    %{
      id: Bus,
      type: :supervisor,
      start:
        {Supervisor, :start_link,
         [[child], [strategy: :one_for_one, max_restarts: 1_000, max_seconds: 60]]}
    }
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: opts[:name])

  @impl true
  def init(opts) do
    {:ok,
     %{
       repo: Keyword.get(opts, :repo, Dawarich.Jobs.repo()),
       namespace: Keyword.get(opts, :namespace, Bus.prefix() || ""),
       pubsub: Keyword.get(opts, :pubsub, Dawarich.PubSub),
       cursor: 0
     }}
  end

  def subscribe(broadcasting, opts \\ []) do
    {server, pubsub, namespace} = options(opts)
    key = key(pubsub, namespace, broadcasting)

    case Process.get(key) do
      %{ref: ref} ->
        send(self(), {:cable_pg, pubsub, namespace, :subscribed, broadcasting, ref})
        {:ok, ref}

      nil ->
        :ok = Phoenix.PubSub.subscribe(pubsub, topic(namespace, broadcasting))
        ref = make_ref()

        case GenServer.call(server, {:fence, self(), broadcasting, ref}) do
          {:ok, fence} ->
            Process.put(key, %{ref: ref, seq: fence})
            {:ok, ref}

          {:error, reason} ->
            Phoenix.PubSub.unsubscribe(pubsub, topic(namespace, broadcasting))
            {:error, reason}
        end
    end
  end

  def unsubscribe(broadcasting, opts \\ []) do
    {_server, pubsub, namespace} = options(opts)
    state = Process.delete(key(pubsub, namespace, broadcasting))
    :ok = Phoenix.PubSub.unsubscribe(pubsub, topic(namespace, broadcasting))
    {:ok, if(state, do: state.ref, else: make_ref())}
  end

  def event({:cable_pg, pubsub, namespace, :subscribed, broadcasting, ref}) do
    case Process.get(key(pubsub, namespace, broadcasting)) do
      %{ref: ^ref} -> {:subscribed, broadcasting}
      _ -> :ignore
    end
  end

  def event({:cable_pg, pubsub, namespace, broadcasting, seq, payload}) when is_integer(seq) do
    key = key(pubsub, namespace, broadcasting)

    case Process.get(key) do
      %{seq: last} = state when seq > last ->
        Process.put(key, %{state | seq: seq})
        {:message, broadcasting, payload}

      _ ->
        :ignore
    end
  end

  def event(_), do: :ignore

  @impl true
  def handle_call({:fence, subscriber, broadcasting, ref}, _from, state) do
    case PgStore.head(state.repo, state.namespace) do
      {:ok, fence} ->
        send(
          subscriber,
          {:cable_pg, state.pubsub, state.namespace, :subscribed, broadcasting, ref}
        )

        {:reply, {:ok, fence}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:poll, state) do
    {:ok, snapshot} = PgStore.snapshot(state.repo, state.namespace, state.cursor)

    cursor =
      Enum.reduce(snapshot.events, state.cursor, fn [seq, broadcasting, payload], _cursor ->
        :ok =
          Phoenix.PubSub.local_broadcast(
            state.pubsub,
            topic(state.namespace, broadcasting),
            {:cable_pg, state.pubsub, state.namespace, broadcasting, seq, payload}
          )

        seq
      end)

    {:noreply, %{state | cursor: cursor}}
  end

  defp options(opts) do
    opts = Keyword.merge(Application.get_env(:dawarich, :cable, []), opts)

    {Keyword.get(opts, :server, Bus), Keyword.get(opts, :pubsub, Dawarich.PubSub),
     Keyword.get(opts, :namespace, Bus.prefix() || "")}
  end

  defp key(pubsub, namespace, broadcasting), do: {__MODULE__, pubsub, namespace, broadcasting}
  defp topic("", broadcasting), do: broadcasting
  defp topic(namespace, broadcasting), do: namespace <> ":" <> broadcasting
end
