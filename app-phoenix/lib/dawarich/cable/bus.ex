defmodule Dawarich.Cable.Bus do
  @moduledoc false

  alias Dawarich.{RailsSecret, Redis}

  @name __MODULE__
  @prefixes %{
    "development" => "dawarich_development",
    "production" => "dawarich_production",
    "staging" => "dawarich_staging"
  }

  def child_specs(config \\ Application.get_env(:dawarich, :cable, [])) do
    if Keyword.get(config, :bus, true) do
      url = if config[:url] in [nil, ""], do: "redis://localhost:6379", else: config[:url]

      options =
        [name: @name, database: config[:database], sync_connect: false] ++
          Redis.socket_options(url)

      [%{id: @name, start: {Redix.PubSub, :start_link, [url, options]}}]
    else
      []
    end
  end

  def prefix(env \\ System.get_env()) do
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
    do: Redis.command(["PUBLISH", channel(broadcasting), payload])

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
