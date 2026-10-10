defmodule Dawarich.Imports.Tempfiles do
  @moduledoc false
  def with_files(fun) do
    owner = self()
    guard = spawn(fn -> loop(Process.monitor(owner), []) end)

    adopt = fn path ->
      tag = make_ref()
      send(guard, {:adopt, owner, tag, path})
      receive do: ({^tag, :adopted} -> :ok)
    end

    try do
      fun.(adopt)
    after
      tag = make_ref()
      send(guard, {:release, owner, tag})
      receive do: ({^tag, :cleaned} -> :ok)
    end
  end

  defp loop(ref, paths) do
    receive do
      {:adopt, owner, tag, path} ->
        send(owner, {tag, :adopted})
        loop(ref, [path | paths])

      {:release, owner, tag} ->
        cleanup(paths)
        Process.demonitor(ref, [:flush])
        send(owner, {tag, :cleaned})

      {:DOWN, ^ref, :process, _, _} ->
        cleanup(paths)
    end
  end

  defp cleanup(paths), do: paths |> Enum.uniq() |> Enum.each(&File.rm/1)
end
