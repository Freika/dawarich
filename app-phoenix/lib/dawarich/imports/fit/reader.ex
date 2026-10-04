defmodule Dawarich.Imports.Fit.Reader do
  @moduledoc false
  import Bitwise
  alias Dawarich.Imports.Fit.{Crc, Definitions, Fields}

  def reduce(path, acc, fun) do
    File.open!(path, [:read, :binary, :raw], fn file ->
      entities(file, File.stat!(path).size, %{}, MapSet.new(), acc, fun)
    end)
  end

  defp entities(file, size, definitions, descriptions, acc, fun) do
    {:ok, offset} = :file.position(file, :cur)

    if offset == size do
      acc
    else
      <<header_size, _, _::little-16, data_size::little-32, kind::binary-size(4)>> =
        Definitions.bytes(file, 12)

      unless header_size in [12, 14],
        do: raise(ArgumentError, "Unsupported header size #{header_size}")

      unless kind == ".FIT", do: raise(ArgumentError, "Unknown file type #{kind}")

      if header_size == 14 do
        <<crc::little-16>> = Definitions.bytes(file, 2)

        if crc != 0 and crc != Crc.range(file, offset, 12),
          do: raise(ArgumentError, "CRC mismatch in header.")
      end

      finish = offset + header_size + data_size
      start = if header_size == 14, do: offset + header_size, else: offset
      Crc.range(file, start, finish - start)

      case :file.pread(file, finish, 2) do
        {:ok, <<_::little-16>>} -> :ok
        _ -> raise ArgumentError, "Premature end of file"
      end

      {definitions, descriptions, acc} =
        records(file, finish, definitions, descriptions, acc, fun)

      :file.position(file, finish + 2)
      entities(file, size, definitions, descriptions, acc, fun)
    end
  end

  defp records(file, finish, definitions, descriptions, acc, fun) do
    {:ok, position} = :file.position(file, :cur)

    if position >= finish do
      {definitions, descriptions, acc}
    else
      <<header>> = Definitions.bytes(file, 1)
      compressed = (header &&& 128) != 0
      local = if compressed, do: header >>> 5 &&& 3, else: header &&& 15

      if not compressed and (header &&& 64) != 0 do
        definition = Definitions.read(file, header, descriptions)
        records(file, finish, Map.put(definitions, local, definition), descriptions, acc, fun)
      else
        definition =
          definitions[local] || raise(ArgumentError, "Undefined local message type: #{local}")

        if compressed, do: Definitions.bytes(file, 1)
        values = Fields.read(file, definition)

        descriptions =
          if definition.number == 206,
            do: MapSet.put(descriptions, {values[0], values[1]}),
            else: descriptions

        acc =
          if definition.number in [18, 19, 20],
            do:
              fun.(
                %{
                  "number" => definition.number,
                  "fields" => Fields.selected(definition.number, values)
                },
                acc
              ),
            else: acc

        records(file, finish, definitions, descriptions, acc, fun)
      end
    end
  end
end
