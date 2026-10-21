defmodule Dawarich.Test.NativeMapBus do
  @moduledoc false
  def subscribe(topic) do
    send(
      Application.get_env(:dawarich, :native_map_bus_owner, self()),
      {:native_subscribe, topic}
    )

    {:ok, make_ref()}
  end

  def unsubscribe(topic, _ref), do: unsubscribe(topic)

  def unsubscribe(topic) do
    send(
      Application.get_env(:dawarich, :native_map_bus_owner, self()),
      {:native_unsubscribe, topic}
    )

    {:ok, make_ref()}
  end

  def event({:native_message, topic, payload}), do: {:message, topic, payload}
  def event(_), do: :ignore
end
