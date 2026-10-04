defmodule Dawarich.Cable.PgBus do
  @moduledoc false
  use GenServer
  require Logger

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
    repo = Keyword.get(opts, :repo, Dawarich.Jobs.repo())
    namespace = Keyword.get(opts, :namespace, Bus.prefix() || "")
    {:ok, cursor} = PgStore.head(repo, namespace)

    state = %{
      repo: repo,
      namespace: namespace,
      pubsub: Keyword.get(opts, :pubsub, Dawarich.PubSub),
      cursor: cursor,
      polling: Keyword.get(opts, :polling, true),
      poll: Keyword.get(opts, :poll, 200),
      clock: Keyword.get(opts, :clock),
      backoff: Keyword.get(opts, :backoff, 5_000)
    }

    {:ok, schedule(state, state.poll)}
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
    case read(state) do
      {:ok, snapshot} ->
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

        delay = if length(snapshot.events) == 100, do: 0, else: state.poll
        {:noreply, schedule(%{state | cursor: cursor}, delay)}

      {:error, reason} ->
        Logger.warning("[Cable] PG poll: #{inspect(error_class(reason))}")
        {:noreply, schedule(state, state.backoff)}
    end
  end

  defp read(state) do
    PgStore.snapshot(state.repo, state.namespace, state.cursor, state.clock)
  rescue
    error -> {:error, error.__struct__}
  catch
    kind, _ -> {:error, kind}
  end

  defp error_class(%{__struct__: kind}), do: kind
  defp error_class(kind) when is_atom(kind), do: kind
  defp error_class(_), do: :query_error

  defp schedule(state, delay) do
    if state.polling, do: Process.send_after(self(), :poll, delay)
    state
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
