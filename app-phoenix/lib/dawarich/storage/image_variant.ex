defmodule Dawarich.Storage.ImageVariant do
  @moduledoc false
  alias Dawarich.Storage

  def transform!(service, blob, variation, dir) do
    source = Path.join(dir, "input")
    download!(service, blob.key, source)
    {checksum, _} = Storage.digest_file!(source)
    composed = Jason.decode!(blob.metadata || "{}")["composed"]

    if !composed and checksum != blob.checksum,
      do: raise(ArgumentError, "ActiveStorage integrity error")

    format = variation.transformations["format"] || "png"

    if format_type(format) == :error,
      do: raise(ArgumentError, "Invalid variant format")

    source
  end

  def preview!(service, blob, dir) do
    source = Path.join(dir, "input")
    download!(service, blob.key, source)
    {checksum, _} = Storage.digest_file!(source)
    composed = Jason.decode!(blob.metadata || "{}")["composed"]

    if !composed and checksum != blob.checksum,
      do: raise(ArgumentError, "ActiveStorage integrity error")

    {tool, args, format, type} =
      if blob.content_type == "application/pdf" do
        {"pdftoppm", ["-singlefile", "-cropbox", "-r", "72", "-png", source], "png", "image/png"}
      else
        {"ffmpeg", ["-i", source, "-y", "-vframes", "1", "-f", "image2", "-"], "jpg",
         "image/jpeg"}
      end

    executable = System.find_executable(tool) || raise(ArgumentError, "No previewer found")

    port =
      Port.open({:spawn_executable, executable}, [:binary, :exit_status, :use_stdio, args: args])

    output = Path.join(dir, "preview")
    File.open!(output, [:write, :binary], fn io -> collect(port, io) end)
    {output, format, type}
  end

  def format_type(format) when is_binary(format) do
    type = MIME.type(format)
    if format in MIME.extensions(type), do: {:ok, type}, else: :error
  end

  def format_type(_), do: :error

  def identify(path, declared) do
    bytes = File.open!(path, [:read, :binary], &IO.binread(&1, 32))

    case bytes do
      <<137, "PNG", _::binary>> ->
        "image/png"

      <<255, 216, 255, _::binary>> ->
        "image/jpeg"

      <<"GIF8", _::binary>> ->
        "image/gif"

      <<"RIFF", _::binary-size(4), "WEBP", _::binary>> ->
        "image/webp"

      <<"BM", _::binary>> ->
        "image/bmp"

      <<"8BPS", _::binary>> ->
        "image/vnd.adobe.photoshop"

      <<0, 0, 1, 0, _::binary>> ->
        "image/vnd.microsoft.icon"

      <<_::binary-size(4), "ftyp", brand::binary-size(4), _::binary>>
      when brand in ["avif", "avis"] ->
        "image/avif"

      <<_::binary-size(4), "ftyp", brand::binary-size(4), _::binary>>
      when brand in ["heic", "heix", "hevc", "hevx"] ->
        "image/heic"

      <<_::binary-size(4), "ftyp", brand::binary-size(4), _::binary>>
      when brand in ["mif1", "msf1"] ->
        "image/heif"

      <<"II", 42, 0, _::binary>> ->
        "image/tiff"

      <<"MM", 0, 42, _::binary>> ->
        "image/tiff"

      _ ->
        declared
    end
  end

  defp download!(%{service: "local", root: root}, key, dest) do
    {:ok, path} = Storage.safe_disk_path(root, key)
    File.cp!(path, dest)
  end

  defp download!(service, key, dest), do: Storage.download!(service, key, dest)

  defp collect(port, io) do
    receive do
      {^port, {:data, data}} ->
        IO.binwrite(io, data)
        collect(port, io)

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, _}} ->
        raise "Preview failed"
    end
  end
end
