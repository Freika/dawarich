defmodule Dawarich.Test.M4Crash do
  use GenServer
  def init(state), do: {:ok, state}
  def handle_info(_message, _state), do: raise("m4 handler failed")
end
