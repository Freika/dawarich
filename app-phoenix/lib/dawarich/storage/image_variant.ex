defmodule Dawarich.Storage.ImageVariant do
  @moduledoc false
  alias Dawarich.Storage

  def transform!(service, blob, variation, dir) do
    source = Path.join(dir, "input")
    Storage.download!(service, blob.key, source)
    {checksum, _} = Storage.digest_file!(source)
    if checksum != blob.checksum, do: raise(ArgumentError, "ActiveStorage integrity error")
    format = variation.transformations["format"] || "png"
    if format not in ~w(png jpg jpeg gif webp avif tiff tif bmp ico heic heif pdf ps), do: raise(ArgumentError, "Invalid variant format")
    source
  end

  def preview!(service, blob, dir) do
    source = Path.join(dir, "input")
    Storage.download!(service, blob.key, source)
    {checksum, _} = Storage.digest_file!(source)
    if checksum != blob.checksum, do: raise(ArgumentError, "ActiveStorage integrity error")
    {tool, args, format, type} =
      if blob.content_type == "application/pdf" do
        {"pdftoppm", ["-singlefile", "-cropbox", "-r", "72", "-png", source], "png", "image/png"}
      else
        {"ffmpeg", ["-i", source, "-y", "-vframes", "1", "-f", "image2", "-"], "jpg", "image/jpeg"}
      end
    executable = System.find_executable(tool) || raise(ArgumentError, "No previewer found")
    port = Port.open({:spawn_executable, executable}, [:binary, :exit_status, :use_stdio, args: args])
    output = Path.join(dir, "preview")
    File.open!(output, [:write, :binary], fn io -> collect(port, io) end)
    {output, format, type}
  end

  defp collect(port, io) do
    receive do
      {^port, {:data, data}} -> IO.binwrite(io, data); collect(port, io)
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, _}} -> raise "Preview failed"
    end
  end
end
