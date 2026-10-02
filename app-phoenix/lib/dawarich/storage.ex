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

  @aws ~w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_BUCKET)
  @external_resource approximations = Path.expand("../../priv/i18n_approximations.json", __DIR__)
  @approximations approximations |> File.read!() |> Jason.decode!()

  def config!(env, rails_root \\ File.cwd!()) do
    root = Path.join(rails_root, "storage")

    case Map.get(env, "STORAGE_BACKEND", "local") do
      "local" -> %{service: "local", root: root}
      "s3" -> Map.merge(%{service: "s3", root: root}, Dawarich.Storage.S3.config!(env))
      other -> raise ArgumentError, "unsupported STORAGE_BACKEND #{inspect(other)}"
    end
  end

  def services!(env, rails_root \\ File.cwd!()) do
    disk = %{
      "test" => %{service: "local", root: Path.join(rails_root, "tmp/storage")},
      "local" => %{service: "local", root: Path.join(rails_root, "storage")}
    }

    services =
      if Enum.all?(@aws, &(Map.get(env, &1) not in [nil, ""])),
        do: Map.put(disk, "s3", config!(Map.put(env, "STORAGE_BACKEND", "s3"), rails_root)),
        else: disk

    %{default: Map.get(env, "STORAGE_BACKEND", "local"), services: services}
  end

  def service!(%{services: services}, name) do
    case Map.fetch(services, name) do
      {:ok, config} -> Map.put(config, :stored_service, name)
      :error -> raise KeyError, "Missing configuration for the #{name} Active Storage service"
    end
  end

  def disk_service(%{default: default, services: services} = registry, name),
    do: service!(registry, if(Map.has_key?(services, name), do: name, else: default))

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

  def put!(config, path, filename, content_type, key \\ nil) do
    {checksum, size} = digest_file!(path)
    key = key || generate_key()

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

  def download!(%{service: "local", root: root}, key, dest),
    do: File.cp!(disk_path(root, key), dest)

  def download!(%{service: "s3"} = config, key, dest),
    do: Dawarich.Storage.S3.download!(config, key, dest)

  def delete(%{service: "local", root: root}, key) do
    _ = File.rm(disk_path(root, key))
    :ok
  end

  def delete(%{service: "s3"} = config, key), do: Dawarich.Storage.S3.delete(config, key)

  def get!(config, key) do
    dir = tmp_dir!(config, "get-" <> generate_key())
    path = Path.join(dir, "object")

    try do
      download!(config, key, path)
      File.read!(path)
    after
      File.rm_rf(dir)
    end
  end

  def sweep_tmp(%{root: root}, max_age_seconds) do
    cutoff = System.os_time(:second) - max_age_seconds

    for dir <- Path.wildcard(Path.join([root, ".phoenix-tmp", "*"])),
        match?({:ok, %File.Stat{mtime: mtime}} when mtime < cutoff, File.stat(dir, time: :posix)),
        do: File.rm_rf(dir)

    :ok
  end

  def sanitized_filename(filename),
    do: filename |> Dawarich.ReleaseMigration.ruby_strip() |> String.replace(@unsafe, "-")

  def content_disposition(type, filename) do
    name = sanitized_filename(filename)
    ascii = Regex.replace(~r/[^\x00-\x7F]/u, name, &Map.get(@approximations, &1, "?"))

    ~s(#{type}; filename="#{escape(ascii, @ascii_escape)}"; filename*=UTF-8''#{escape(name, @utf8_escape)})
  end

  def safe_disk_path(root, key) when is_binary(key) do
    root = Path.expand(root)
    segments = String.split(key, "/")

    with true <-
           String.valid?(key) and String.trim(key) != "" and not String.contains?(key, <<0>>),
         false <- "." in segments or ".." in segments,
         codepoints = String.codepoints(key),
         path = Path.expand(Path.join([root, folder(codepoints, 0), folder(codepoints, 2), key])),
         true <- String.starts_with?(path, root <> "/") do
      {:ok, path}
    else
      _ -> :error
    end
  end

  def safe_disk_path(_root, _key), do: :error

  defp folder(codepoints, at), do: codepoints |> Enum.slice(at, 2) |> Enum.join()

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
