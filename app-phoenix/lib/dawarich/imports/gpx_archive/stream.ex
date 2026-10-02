defmodule Dawarich.Imports.GpxArchive.Stream do
  @moduledoc false
  alias Dawarich.Imports.GpxArchive.{Directory, Error}
  @chunk 65_536

  def consume!(file, entry, central, sink, limit) do
    if entry.size > limit, do: raise(Error, message: "ZIP entry exceeds extracted byte budget")
    position = Directory.data!(file, entry, central)

    {crc, size} =
      if entry.method == 0 do
        copy!(file, position, entry.compressed, sink, limit, {0, 0})
      else
        z = :zlib.open()

        try do
          :ok = :zlib.inflateInit(z, -15, :error)
          result = inflate!(z, file, position, entry.compressed, sink, limit, {0, 0})
          :ok = :zlib.inflateEnd(z)
          result
        after
          :zlib.close(z)
        end
      end

    unless crc == entry.crc and size == entry.size,
      do: raise(Error, message: "ZIP entry checksum or size mismatch")

    :ok
  rescue
    ErlangError -> raise Error, message: "Invalid or truncated ZIP deflate stream"
  end

  def prefix!(file, entry, central, limit) do
    tag = make_ref()
    chunks = :ets.new(__MODULE__, [:ordered_set, :private])
    :ets.insert(chunks, {:size, 0})

    try do
      sink = fn data ->
        current = :ets.lookup_element(chunks, :size, 2)
        remaining = max(limit - current, 0)
        take = binary_part(data, 0, min(byte_size(data), remaining))
        :ets.insert(chunks, {current, take})
        :ets.insert(chunks, {:size, current + byte_size(take)})
        if current + byte_size(data) >= limit, do: throw({tag, :done})
      end

      try do
        consume!(file, entry, central, sink, max(entry.size, limit))
      catch
        {^tag, :done} -> :ok
      end

      for {key, data} <- :ets.tab2list(chunks), is_integer(key), into: <<>>, do: data
    after
      :ets.delete(chunks)
    end
  end

  defp copy!(_file, _position, 0, _sink, _limit, state), do: state

  defp copy!(file, position, left, sink, limit, state) do
    size = min(left, @chunk)
    data = Directory.read!(file, position, size)
    state = emit!(sink, data, limit, state)
    copy!(file, position + size, left - size, sink, limit, state)
  end

  defp inflate!(_z, _file, _position, 0, _sink, _limit, state), do: state

  defp inflate!(z, file, position, left, sink, limit, state) do
    size = min(left, @chunk)
    data = Directory.read!(file, position, size)
    state = drain!(z, :zlib.safeInflate(z, data), sink, limit, state)
    inflate!(z, file, position + size, left - size, sink, limit, state)
  end

  defp drain!(z, {:continue, output}, sink, limit, state) do
    state = emit!(sink, IO.iodata_to_binary(output), limit, state)
    drain!(z, :zlib.safeInflate(z, []), sink, limit, state)
  end

  defp drain!(_z, {:finished, output}, sink, limit, state),
    do: emit!(sink, IO.iodata_to_binary(output), limit, state)

  defp drain!(_z, _, _sink, _limit, _state),
    do: raise(Error, message: "Unsupported ZIP dictionary")

  defp emit!(sink, data, limit, {crc, size}) do
    size = size + byte_size(data)
    if size > limit, do: raise(Error, message: "ZIP entry exceeds extracted byte budget")
    sink.(data)
    {:erlang.crc32(crc, data), size}
  end
end
