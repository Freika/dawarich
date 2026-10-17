defmodule Dawarich.Imports.GpxArchive.Directory do
  @moduledoc false
  import Bitwise
  alias Dawarich.Imports.GpxArchive.Error
  @max32 0xFFFFFFFF

  def read!(file, opts) do
    {:ok, total} = :file.position(file, :eof)
    offset = max(total - 65_557, 0)
    tail = read!(file, offset, total - offset)
    candidates = :binary.matches(tail, <<0x06054B50::little-32>>) |> Enum.reverse()

    trailer =
      Enum.find_value(candidates, fn {at, _} ->
        case binary_part(tail, at, byte_size(tail) - at) do
          <<0x06054B50::little-32, disk::little-16, cd_disk::little-16, on_disk::little-16,
            count::little-16, size::little-32, position::little-32, comment::little-16,
            rest::binary>>
          when byte_size(rest) == comment ->
            %{
              disk: disk,
              cd_disk: cd_disk,
              on_disk: on_disk,
              count: count,
              size: size,
              position: position,
              trailer: offset + at
            }

          _ ->
            nil
        end
      end) || fail!("ZIP central directory is missing")

    unless trailer.disk == 0 and trailer.cd_disk == 0 and trailer.on_disk == trailer.count,
      do: fail!("Split ZIP archives are not supported")

    trailer = zip64!(file, trailer)

    if exceeds?(trailer.size, Keyword.get(opts, :max_directory_bytes, 16_777_216)),
      do: fail!("ZIP central directory exceeds metadata budget")

    if exceeds?(trailer.count, Keyword.get(opts, :max_entries, 25_000)),
      do: fail!("ZIP entry count exceeds budget")

    unless trailer.position >= 0 and trailer.position + trailer.size == trailer.trailer,
      do: fail!("ZIP central directory bounds are invalid")

    {entries, ending} =
      entries!(file, trailer.position, trailer.count, [], trailer.position + trailer.size)

    unless ending == trailer.position + trailer.size,
      do: fail!("ZIP central directory size does not match")

    unless Keyword.get(opts, :path_policy) == :user_data do
      names = Enum.map(entries, & &1.name)
      if length(Enum.uniq(names)) != length(names), do: fail!("Duplicate ZIP entry names")
      Enum.each(entries, &safe!/1)
    end

    %{entries: entries, offset: trailer.position}
  end

  def supported?(entry), do: entry.method in [0, 8] and band(entry.flags, bnot(0x080E)) == 0

  def data!(file, entry, central_offset) do
    <<0x04034B50::little-32, _version::little-16, flags::little-16, method::little-16, _time::32,
      crc::little-32, compressed::little-32, size::little-32, nlen::little-16, xlen::little-16>> =
      read!(file, entry.offset, 30)

    name = read!(file, entry.offset + 30, nlen)
    extra = read!(file, entry.offset + 30 + nlen, xlen)

    unless name == entry.name and method == entry.method and flags == entry.flags,
      do: fail!("ZIP local and central headers disagree")

    descriptor? = band(flags, 8) != 0

    if not descriptor? do
      {size, compressed, _offset} = sizes!(size, compressed, 0, extra)

      unless crc == entry.crc and size == entry.size and compressed == entry.compressed,
        do: fail!("ZIP local sizes or checksum disagree")
    end

    position = entry.offset + 30 + nlen + xlen

    unless entry.offset >= 0 and position + entry.compressed <= central_offset,
      do: fail!("ZIP entry data overlaps central directory")

    if descriptor?, do: descriptor!(file, position + entry.compressed, entry, central_offset)
    position
  end

  def read!(_file, _position, 0), do: <<>>

  def read!(file, position, length) when position >= 0 and length > 0 do
    case :file.pread(file, position, length) do
      {:ok, data} when byte_size(data) == length -> data
      _ -> fail!("Truncated ZIP archive")
    end
  end

  defp entries!(_file, position, 0, entries, _ending), do: {Enum.reverse(entries), position}

  defp entries!(file, position, count, entries, ending) do
    unless position + 46 <= ending, do: fail!("Truncated ZIP directory entry")

    <<0x02014B50::little-32, made::little-16, _version::little-16, flags::little-16,
      method::little-16, _time::32, crc::little-32, compressed::little-32, size::little-32,
      nlen::little-16, xlen::little-16, clen::little-16, disk::little-16, _attrs::little-16,
      attrs::little-32, offset::little-32>> = read!(file, position, 46)

    next = position + 46 + nlen + xlen + clen
    unless disk == 0 and next <= ending, do: fail!("Invalid ZIP directory entry")
    name = read!(file, position + 46, nlen)
    extra = read!(file, position + 46 + nlen, xlen)
    zip64 = size == @max32 or compressed == @max32
    {size, compressed, offset} = sizes!(size, compressed, offset, extra)

    entry = %{
      name: name,
      method: method,
      flags: flags,
      crc: crc,
      compressed: compressed,
      size: size,
      offset: offset,
      unix: made >>> 8 == 3,
      attrs: attrs,
      zip64: zip64
    }

    entries!(file, next, count - 1, [entry | entries], ending)
  end

  defp sizes!(size, compressed, offset, extra) do
    fields = extras!(extra, %{})
    data = Map.get(fields, 1, <<>>)
    {size, data} = value64!(size, data)
    {compressed, data} = value64!(compressed, data)
    {offset, _data} = value64!(offset, data)
    {size, compressed, offset}
  end

  defp value64!(@max32, <<value::little-64, rest::binary>>), do: {value, rest}
  defp value64!(@max32, _), do: fail!("ZIP64 size metadata is missing")
  defp value64!(value, data), do: {value, data}
  defp extras!(<<>>, fields), do: fields

  defp extras!(
         <<tag::little-16, length::little-16, data::binary-size(length), rest::binary>>,
         fields
       ) do
    if Map.has_key?(fields, tag), do: fail!("Duplicate ZIP extra metadata")
    extras!(rest, Map.put(fields, tag, data))
  end

  defp extras!(_, _), do: fail!("Invalid ZIP extra metadata")

  defp zip64!(file, %{count: count, size: size, position: position} = trailer)
       when count == 0xFFFF or size == @max32 or position == @max32 do
    <<0x07064B50::little-32, 0::32, offset::little-64, 1::little-32>> =
      read!(file, trailer.trailer - 20, 20)

    <<0x06064B50::little-32, length::little-64, _made::16, _need::16, 0::32, 0::32,
      count::little-64, count::little-64, size::little-64, position::little-64>> =
      read!(file, offset, 56)

    unless length >= 44 and offset + 12 + length == trailer.trailer - 20,
      do: fail!("Invalid ZIP64 trailer")

    %{trailer | count: count, size: size, position: position, trailer: offset}
  end

  defp zip64!(_file, trailer), do: trailer

  defp descriptor!(file, position, entry, central) do
    size_length = if entry.zip64, do: 8, else: 4
    first = read!(file, position, 4)
    position = if first == <<0x08074B50::little-32>>, do: position + 4, else: position

    unless position + 4 + size_length * 2 <= central,
      do: fail!("ZIP descriptor overlaps directory")

    <<crc::little-32, sizes::binary>> = read!(file, position, 4 + size_length * 2)

    {compressed, size} =
      if size_length == 8 do
        <<compressed::little-64, size::little-64>> = sizes
        {compressed, size}
      else
        <<compressed::little-32, size::little-32>> = sizes
        {compressed, size}
      end

    unless {crc, compressed, size} == {entry.crc, entry.compressed, entry.size},
      do: fail!("ZIP descriptor disagrees")
  end

  defp safe!(entry) do
    name = entry.name

    if name == <<>> or :binary.match(name, <<0>>) != :nomatch or
         String.starts_with?(name, "/") or :binary.match(name, "\\") != :nomatch or
         Regex.match?(~r/\A[A-Za-z]:/, name) or ".." in :binary.split(name, "/", [:global]),
       do: fail!("Unsafe ZIP entry path")

    mode = entry.attrs >>> 16 &&& 0o170000

    if entry.unix and mode not in [0, 0o100000, 0o040000],
      do: fail!("ZIP entry is not a regular file or directory")
  end

  defp exceeds?(_value, :infinity), do: false
  defp exceeds?(value, limit), do: value > limit
  defp fail!(message), do: raise(Error, message: message)
end
