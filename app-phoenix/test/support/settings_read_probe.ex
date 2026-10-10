defmodule Dawarich.Test.SettingsReadProbe do
  def run(pid, fragment, change, action) do
    ref = make_ref()
    id = "settings-read-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        id,
        [:dawarich, :repo, :query],
        &__MODULE__.after_read/4,
        {pid, self(), ref, fragment, change}
      )

    try do
      {action.(), ref}
    after
      :telemetry.detach(id)
      Process.delete(ref)
    end
  end

  def after_read(_, _, %{query: query}, {pid, owner, ref, fragment, change}) do
    if self() == pid and String.contains?(query, fragment) and not Process.get(ref, false) do
      Process.put(ref, true)
      change.()
      send(owner, {:settings_read_probe, ref})
    end
  end
end
