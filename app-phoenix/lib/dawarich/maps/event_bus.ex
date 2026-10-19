defmodule Dawarich.Maps.EventBus do
  @moduledoc false
  alias Dawarich.Cable.Bus
  @family [:membership, :consent, :request, :invitation, :lapse, :location]

  def subscribe(topic) do
    cond do
      native?(topic) and topic in Registry.keys(Dawarich.PubSub, self()) ->
        {:ok, {:shared, topic}}

      native?(topic) ->
        case Phoenix.PubSub.subscribe(Dawarich.PubSub, topic) do
          :ok -> {:ok, topic}
          error -> error
        end

      true ->
        Bus.subscribe(topic)
    end
  end

  def unsubscribe(_topic, {:shared, _}), do: :ok
  def unsubscribe(topic, _ref), do: unsubscribe(topic)

  def unsubscribe(topic) do
    if native?(topic),
      do: Phoenix.PubSub.unsubscribe(Dawarich.PubSub, topic),
      else: Bus.unsubscribe(topic)
  end

  def event({:domain_changed, user, kind}) when is_integer(user) and kind in @family,
    do: {:domain_message, "family:user:#{user}"}

  def event({:domain_changed, user, :imports}) when is_integer(user),
    do: {:domain_message, "imports:user:#{user}:native"}

  def event({:domain_changed, user, kind})
      when is_integer(user) and kind in [:notifications, :sharing],
      do: {:domain_message, "#{kind}:user:#{user}"}

  def event({:share_invalidated, reference}) when is_binary(reference),
    do: {:domain_message, "sharing:public:" <> reference}

  def event(message), do: Bus.event(message)

  defp native?(topic),
    do:
      String.starts_with?(topic, [
        "family:user:",
        "imports:user:",
        "notifications:user:",
        "sharing:"
      ])
end
