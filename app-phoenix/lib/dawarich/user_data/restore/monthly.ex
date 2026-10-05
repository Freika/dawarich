defmodule Dawarich.UserData.Restore.Monthly do
  @moduledoc false
  alias Dawarich.UserData.{Jsonl, Paths}

  def call(module, repo, user, directory, manifest, name, context) do
    files = get_in(manifest, ["files", name]) || []
    files = if files == [], do: [name <> ".jsonl"], else: Enum.sort(files)

    Enum.reduce(files, 0, fn relative, count ->
      path = Paths.relative(directory, relative)

      if path && File.regular?(path) do
        stream =
          path
          |> File.stream!()
          |> Stream.map(&String.trim/1)
          |> Stream.reject(&(&1 == ""))
          |> Stream.map(&Jsonl.decode!/1)

        size = if name == "visits", do: 5000, else: 1000

        stream
        |> Stream.chunk_every(size)
        |> Enum.reduce(count, fn batch, total ->
          total + module.call(repo, user, batch, context)
        end)
      else
        count
      end
    end)
  end
end
