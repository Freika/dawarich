defmodule Dawarich.Test.NativePageCache do
  @moduledoc false
  def start do
    {:ok,
     ExUnit.Callbacks.start_supervised!(
       {Agent, fn -> %{now: 1_790_000_000, entries: %{}, commands: [], failure: nil} end}
     )}
  end

  def now(pid), do: Agent.get(pid, & &1.now)
  def advance(pid, seconds), do: Agent.update(pid, &%{&1 | now: &1.now + seconds})
  def entries(pid), do: Agent.get(pid, & &1.entries)
  def commands(pid), do: Agent.get(pid, & &1.commands)
  def failure(pid, failure), do: Agent.update(pid, &%{&1 | failure: failure})

  def corrupt(pid, key, bytes),
    do: Agent.update(pid, &put_in(&1.entries[key], {bytes, &1.now + 86400}))

  def command(pid, command) do
    Agent.get_and_update(pid, fn state ->
      state = %{state | commands: state.commands ++ [command]}

      case {state.failure, command} do
        {:read, ["GET", _]} ->
          {{:error, :unavailable}, state}

        {:ttl, ["SET" | _]} ->
          {{:error, :unavailable}, state}

        {_, ["GET", key]} ->
          case state.entries[key] do
            {bytes, expiry} when expiry > state.now -> {{:ok, bytes}, state}
            _ -> {{:ok, nil}, state}
          end

        {_, ["SET", key, bytes, "EX", seconds]} ->
          {{:ok, "OK"},
           put_in(state.entries[key], {bytes, state.now + String.to_integer(seconds)})}

        {_, ["UNLINK", key]} ->
          {{:ok, 1}, %{state | entries: Map.delete(state.entries, key)}}

        _ ->
          {{:error, :invalid_command}, state}
      end
    end)
  end

  def options(pid),
    do: [
      command: &command(pid, &1),
      clock: fn -> now(pid) end,
      after_commit: fn write -> write.() end,
      self_hosted: true
    ]
end
