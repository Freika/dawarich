defmodule Dawarich.Imports.Fit.Crc do
  @moduledoc false
  import Bitwise

  @table {0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401, 0xA001, 0x6C00, 0x7800,
          0xB401, 0x5000, 0x9C01, 0x8801, 0x4400}

  def update(bytes, crc \\ 0) do
    for <<byte <- bytes>>, reduce: crc do
      value ->
        value = bxor(bxor(value >>> 4, elem(@table, value &&& 15)), elem(@table, byte &&& 15))
        bxor(bxor(value >>> 4, elem(@table, value &&& 15)), elem(@table, byte >>> 4))
    end
  end

  def range(file, position, size), do: range(file, position, size, 0)
  defp range(_, _, 0, crc), do: crc

  defp range(file, position, left, crc) do
    size = min(left, 65_536)

    case :file.pread(file, position, size) do
      {:ok, bytes} when byte_size(bytes) == size ->
        range(file, position + size, left - size, update(bytes, crc))

      _ ->
        raise ArgumentError, "Premature end of file"
    end
  end
end
