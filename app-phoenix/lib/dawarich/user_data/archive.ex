defmodule Dawarich.UserData.Archive do
  @moduledoc false
  alias Dawarich.Imports.GpxArchive.{Directory, Error, Stream}
  alias Dawarich.Imports.JsonStream.Spool
  alias Dawarich.UserData.Paths
  @max_entry_bytes 10 * 1024 * 1024 * 1024

  def with_directory(path, context, fun, opts \\ []) do
    Spool.with_directory(context, fn directory ->
      File.open!(path, [:read, :binary], fn archive ->
        central =
          Directory.read!(archive,
            path_policy: :user_data,
            max_entries: :infinity,
            max_directory_bytes: :infinity
          )

        Enum.each(central.entries, fn entry ->
          name = Paths.sanitize(entry.name)

          if name && name != "" && not String.ends_with?(name, "/") do
            target = Paths.relative(directory, name)

            if target do
              unless Directory.supported?(entry),
                do: raise(Error, message: "Unsupported ZIP entry encoding")

              File.mkdir_p!(Path.dirname(target))

              File.open!(target, [:write, :binary], fn file ->
                File.chmod!(target, 0o600)

                Stream.consume!(
                  archive,
                  entry,
                  central.offset,
                  fn bytes ->
                    case IO.binwrite(file, bytes) do
                      :ok ->
                        :ok

                      {:error, reason} ->
                        raise File.Error, reason: reason, action: "write", path: target
                    end
                  end,
                  Keyword.get(opts, :max_entry_bytes, @max_entry_bytes)
                )
              end)
            end
          end
        end)
      end)

      fun.(directory)
    end)
  end
end
