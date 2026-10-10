defmodule Dawarich.Test.NativeSharingCrash do
  @moduledoc false
  use GenServer
  def init(state), do: {:ok, state}
  def handle_info(%Phoenix.Socket.Message{}, _state), do: raise("native sharing event failure")
end
