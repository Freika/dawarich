defmodule Dawarich.Storage do
  @moduledoc false

  @alphabet ~c"0123456789abcdefghijklmnopqrstuvwxyz"
  @metadata ~s({"identified":true,"analyzed":true})
  @ascii_escape ~r/[^ A-Za-z0-9!\#$+.^_`|~-]/
  @utf8_escape ~r/[^A-Za-z0-9!\#$&+.^_`|~-]/
  @unsafe [
    "\u202E",
    "%",
    "$",
    "|",
    ":",
    ";",
    "/",
    "<",
    ">",
    "?",
    "*",
    "\"",
    "\t",
    "\r",
    "\n",
    "\\"
  ]

  def config!(env, rails_root \\ File.cwd!()) do
    root = Path.join(rails_root, "storage")

    case Map.get(env, "STORAGE_BACKEND", "local") do
      "local" -> %{service: "local", root: root}
      "s3" -> Map.merge(%{service: "s3", root: root}, Dawarich.Storage.S3.config!(env))
      other -> raise ArgumentError, "unsupported STORAGE_BACKEND #{inspect(other)}"
    end
  end

  def tmp_dir!(%{root: root}, event_id) do
    dir = Path.join([root, ".phoenix-tmp", event_id])
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  def generate_key, do: for(_ <- 1..28, into: "", do: <<Enum.at(@alphabet, uniform36())>>)

  def disk_path(root, key),
    do: Path.join([root, binary_part(key, 0, 2), binary_part(key, 2, 2), key])

  def digest_file!(path) do
    {ctx, size} =
      path
      |> File.stream!(1_048_576)
      |> Enum.reduce({:crypto.hash_init(:md5), 0}, fn chunk, {ctx, size} ->
        {:crypto.hash_update(ctx, chunk), size + byte_size(chunk)}
      end)

    {Base.encode64(:crypto.hash_final(ctx)), size}
  end

  def put!(config, path, filename, content_type) do
    {checksum, size} = digest_file!(path)
    key = generate_key()

    case config.service do
      "local" ->
        dest = disk_path(config.root, key)
        File.mkdir_p!(Path.dirname(dest))
        File.rename!(path, dest)

      "s3" ->
        headers = %{
          "content-type" => content_type,
          "content-disposition" => content_disposition("attachment", filename)
        }

        Dawarich.Storage.S3.put!(config, path, key, headers, checksum, size)
    end

    %{
      key: key,
      filename: filename,
      content_type: content_type,
      metadata: @metadata,
      service_name: config.service,
      byte_size: size,
      checksum: checksum
    }
  end

  def delete(%{service: "local", root: root}, key) do
    _ = File.rm(disk_path(root, key))
    :ok
  end

  def delete(%{service: "s3"} = config, key), do: Dawarich.Storage.S3.delete(config, key)

  def sweep_tmp(%{root: root}, max_age_seconds) do
    cutoff = System.os_time(:second) - max_age_seconds

    for dir <- Path.wildcard(Path.join([root, ".phoenix-tmp", "*"])),
        match?({:ok, %File.Stat{mtime: mtime}} when mtime < cutoff, File.stat(dir, time: :posix)),
        do: File.rm_rf(dir)

    :ok
  end

  def content_disposition(type, filename) do
    name = filename |> String.trim() |> String.replace(@unsafe, "-")
    ascii = String.replace(name, ~r/[^\x00-\x7F]/u, "?")

    ~s(#{type}; filename="#{escape(ascii, @ascii_escape)}"; filename*=UTF-8''#{escape(name, @utf8_escape)})
  end

  defp escape(string, pattern),
    do:
      Regex.replace(pattern, string, fn char ->
        for <<byte <- char>>, into: "", do: "%" <> Base.encode16(<<byte>>)
      end)

  defp uniform36 do
    <<byte>> = :crypto.strong_rand_bytes(1)
    if byte < 252, do: rem(byte, 36), else: uniform36()
  end
end
