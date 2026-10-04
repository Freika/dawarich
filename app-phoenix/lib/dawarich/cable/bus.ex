defmodule Dawarich.Cable.Bus do
  @moduledoc false

  alias Dawarich.{RailsSecret, Redis}

  @name __MODULE__
  @publisher Dawarich.Cable.Bus.Publisher
  @prefix_key {__MODULE__, :prefix}
  @prefixes %{
    "development" => "dawarich_development",
    "production" => "dawarich_production",
    "staging" => "dawarich_staging"
  }

  def child_specs(config \\ Application.get_env(:dawarich, :cable, [])) do
    cond do
      not Keyword.get(config, :bus, true) ->
        []

      Keyword.get(config, :transport, :redis) == :pg ->
        [Dawarich.Cable.PgBus.child_spec(Keyword.put(config, :name, @name))]

      true ->
        redis_child_specs(config)
    end
  end

  defp redis_child_specs(config) do
    url = if config[:url] in [nil, ""], do: "redis://localhost:6379", else: config[:url]
    database = if config[:database], do: [database: config[:database]], else: []
    base = database ++ [sync_connect: false] ++ Redis.socket_options(url)

    [
      %{id: @name, start: {Redix.PubSub, :start_link, [url, [name: @name] ++ base]}},
      %{
        id: @publisher,
        start:
          {Redix, :start_link, [url, [name: @publisher, exit_on_disconnection: false] ++ base]}
      }
    ]
  end

  def prefix do
    case :persistent_term.get(@prefix_key, nil) do
      {prefix} ->
        prefix

      nil ->
        prefix = prefix(System.get_env())
        :persistent_term.put(@prefix_key, {prefix})
        prefix
    end
  end

  def prefix(env) do
    case Application.fetch_env(:dawarich, :cable_prefix) do
      {:ok, prefix} -> prefix
      :error -> Map.get(@prefixes, RailsSecret.rails_env(env))
    end
  end

  def channel(broadcasting),
    do: Enum.join(Enum.reject([prefix(), broadcasting], &is_nil/1), ":")

  def subscribe(broadcasting), do: Redix.PubSub.subscribe(@name, channel(broadcasting), self())

  def unsubscribe(broadcasting),
    do: Redix.PubSub.unsubscribe(@name, channel(broadcasting), self())

  def publish(broadcasting, payload),
    do: Redis.command(["PUBLISH", channel(broadcasting), payload], @publisher)

  def event({:redix_pubsub, _pid, _ref, :message, %{channel: channel, payload: payload}}),
    do: {:message, strip(channel), payload}

  def event({:redix_pubsub, _pid, _ref, :subscribed, %{channel: channel}}),
    do: {:subscribed, strip(channel)}

  def event(_message), do: :ignore

  defp strip(channel) do
    case prefix() do
      nil -> channel
      prefix -> String.replace_prefix(channel, prefix <> ":", "")
    end
  end
end
