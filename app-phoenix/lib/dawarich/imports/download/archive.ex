defmodule Dawarich.Imports.Download.Archive do
  @moduledoc false
  alias Dawarich.Imports.GpxArchive
  alias GpxArchive.{Directory, Error, Stream}

  def extract!(path, original, opts) do
    case inspect_archive(path, opts) do
      {:entry, %{name: ^original}} -> generic!(path, original, opts)
      _ -> :original
    end
  rescue
    error in Error ->
      if String.contains?(error.message, "exceeds"),
        do: :original,
        else: reraise(error, __STACKTRACE__)
  end

  defp inspect_archive(path, opts) do
    GpxArchive.inspect!(path, opts)
  rescue
    _ in Error -> :original
  end

  defp generic!(path, original, opts) do
    File.open!(path, [:read, :binary, :raw], fn file ->
      %{entries: entries, offset: central} = Directory.read!(file, opts)
      [entry] = Enum.reject(entries, &String.ends_with?(&1.name, "/"))

      if entry.name == original do
        inner =
          Path.join(
            Keyword.fetch!(opts, :temp_dir),
            "unzipped-" <> Dawarich.Storage.generate_key() <> Path.extname(entry.name)
          )

        Keyword.fetch!(opts, :on_verified).(inner)

        File.open!(inner, [:write, :exclusive, :binary, :raw], fn out ->
          File.chmod!(inner, 0o600)

          Stream.consume!(
            file,
            entry,
            central,
            fn chunk -> :ok = :file.write(out, chunk) end,
            Keyword.get(
              opts,
              :max_bytes,
              String.to_integer(System.get_env("ZIP_MAX_EXTRACTED_SIZE", "2147483648"))
            )
          )
        end)

        {:file, inner}
      else
        :original
      end
    end)
  end
end
