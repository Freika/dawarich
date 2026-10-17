defmodule Dawarich.UserData.Versions do
  @moduledoc false
  alias Dawarich.Imports.JsonStream
  alias Dawarich.Imports.JsonStream.Spool
  alias Dawarich.UserData.Jsonl
  @sections ~w(counts settings areas imports exports trips stats notifications)
  @streamed ~w(places visits points)

  defmodule UnsupportedFormatError do
    defexception message: "Unknown export format: neither manifest.json nor data.json found"
  end

  def detect(directory) do
    cond do
      File.exists?(Path.join(directory, "manifest.json")) ->
        version(directory)

      File.exists?(Path.join(directory, "data.json")) ->
        1

      true ->
        raise UnsupportedFormatError
    end
  end

  def manifest(directory) do
    bytes = directory |> Path.join("manifest.json") |> File.read!()

    try do
      Jason.decode!(bytes)
    rescue
      original in Jason.DecodeError ->
        try do
          Jsonl.decode!(bytes)
          reraise original, __STACKTRACE__
        rescue
          error in JsonStream.Error ->
            raise JsonStream.Error, message: Exception.message(error) <> " in '" <> bytes
        end
    end
  end

  defp version(directory) do
    Map.get(manifest(directory), "format_version") || 2
  rescue
    _error in [Jason.DecodeError, JsonStream.Error] -> 2
  end

  def reduce_v1(path, context, acc, fun) do
    Spool.with_directory(context, fn directory ->
      paths = Map.new(["visits", "points"], &{&1, Path.join(directory, &1)})
      writers = Map.new(paths, fn {key, path} -> {key, Spool.open!(path)} end)

      result =
        try do
          JsonStream.reduce(
            path,
            acc,
            fn
              {:value, [name], value, _, _}, acc when name in @sections ->
                fun.({:section, name, Jsonl.value(value)}, acc)

              {:value, [index, "places"], value, _, _}, acc when is_integer(index) ->
                value = Jsonl.value(value)
                if is_map(value), do: fun.({:row, "places", value}, acc), else: acc

              {:value, [index, name], value, _, _}, acc
              when is_integer(index) and name in ["visits", "points"] ->
                value = Jsonl.value(value)
                if value not in [nil, false], do: Spool.write!(Map.fetch!(writers, name), value)
                acc

              _, acc ->
                acc
            end,
            &select_v1/1
          )
        after
          Enum.each(writers, fn {_, writer} -> File.close(writer) end)
        end

      Enum.reduce(["visits", "points"], result, fn name, acc ->
        paths
        |> Map.fetch!(name)
        |> Spool.stream()
        |> Enum.reduce(acc, fn row, acc ->
          fun.({:row, name, row}, acc)
        end)
      end)
    end)
  end

  defp select_v1([name]) when name in @sections, do: true
  defp select_v1([index, name]) when is_integer(index) and name in @streamed, do: true
  defp select_v1(_), do: false
end
