defmodule Dawarich.Exports.Zip do
  @moduledoc false
  import Bitwise

  @max32 0xFFFFFFFF
  @version 45
  @made_by 3 <<< 8 ||| @version
  @unix_file 0o100644 <<< 16
  @chunk 65_536

  def write!(path, source, name) do
    File.open!(path, [:write, :binary, :raw], fn out ->
      central = write_entry!(out, source, name)
      {:ok, offset} = :file.position(out, :cur)
      :ok = :file.write(out, [central, trailer(offset, byte_size(central))])
    end)
  end

  def write_entry!(out, source, name) do
    if String.starts_with?(name, "/") or byte_size(name) > 0xFFFF,
      do: raise(ArgumentError, "invalid zip entry name")

    {:ok, offset} = :file.position(out, :cur)
    {time, date} = dos_time(:calendar.local_time())
    header = local_header(name, time, date)
    :ok = :file.write(out, header)
    {crc, compressed, size} = deflate!(out, source)
    :ok = :file.pwrite(out, offset + 14, <<crc::little-32>>)
    :ok = :file.pwrite(out, offset + byte_size(header) - 20, zip64_sizes(size, compressed))
    central_header(name, time, date, crc, compressed, size, offset)
  end

  def trailer(cd_offset, cd_size, count \\ 1) do
    if cd_offset < @max32 and cd_size < @max32 and count < 0xFFFF do
      [eocd(cd_offset, cd_size, count)]
    else
      [
        <<0x06064B50::little-32, 44::little-64, @made_by::little-16, @version::little-16, 0::32,
          0::32, count::little-64, count::little-64, cd_size::little-64, cd_offset::little-64>>,
        <<0x07064B50::little-32, 0::32, cd_offset + cd_size::little-64, 1::little-32>>,
        eocd(min(cd_offset, @max32), min(cd_size, @max32), min(count, 0xFFFF))
      ]
    end
  end

  defp deflate!(out, source) do
    z = :zlib.open()
    :ok = :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)

    {crc, compressed, size} =
      source
      |> File.stream!(@chunk)
      |> Enum.reduce({0, 0, 0}, fn chunk, {crc, compressed, size} ->
        {:erlang.crc32(crc, chunk), compressed + write!(out, :zlib.deflate(z, chunk, :none)),
         size + byte_size(chunk)}
      end)

    compressed = compressed + write!(out, :zlib.deflate(z, [], :finish))
    :zlib.close(z)
    {crc, compressed, size}
  end

  defp write!(out, data) do
    :ok = :file.write(out, data)
    IO.iodata_length(data)
  end

  defp local_header(name, time, date),
    do:
      <<0x04034B50::little-32, @version::little-16, 0::16, 8::little-16, time::little-16,
        date::little-16, 0::32, @max32::little-32, @max32::little-32, byte_size(name)::little-16,
        20::little-16>> <> name <> zip64_sizes(0, 0)

  defp central_header(name, time, date, crc, compressed, size, offset) do
    extra =
      if offset < @max32,
        do: zip64_sizes(size, compressed),
        else:
          <<1::little-16, 24::little-16, size::little-64, compressed::little-64,
            offset::little-64>>

    <<0x02014B50::little-32, @made_by::little-16, @version::little-16, 0::16, 8::little-16,
      time::little-16, date::little-16, crc::little-32, @max32::little-32, @max32::little-32,
      byte_size(name)::little-16, byte_size(extra)::little-16, 0::16, 0::16, 0::16,
      @unix_file::little-32, min(offset, @max32)::little-32>> <> name <> extra
  end

  defp zip64_sizes(size, compressed),
    do: <<1::little-16, 16::little-16, size::little-64, compressed::little-64>>

  defp eocd(cd_offset, cd_size, count),
    do:
      <<0x06054B50::little-32, 0::32, count::little-16, count::little-16, cd_size::little-32,
        cd_offset::little-32, 0::16>>

  defp dos_time({{year, month, day}, {hour, minute, second}}),
    do:
      {hour <<< 11 ||| minute <<< 5 ||| div(second, 2),
       (year - 1980) <<< 9 ||| month <<< 5 ||| day}
end
