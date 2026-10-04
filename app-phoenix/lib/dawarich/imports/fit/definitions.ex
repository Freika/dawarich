defmodule Dawarich.Imports.Fit.Definitions do
  @moduledoc false
  import Bitwise

  def read(file, header, descriptions) do
    <<_, architecture, number::binary-size(2), count>> = bytes(file, 5)
    if architecture > 1, do: raise(ArgumentError, "Illegal architecture value #{architecture}")
    endian = if architecture == 0, do: :little, else: :big
    number = :binary.decode_unsigned(number, endian)
    fields = for <<id, size, type <- bytes(file, count * 3)>>, do: {id, size, type &&& 31}

    developer =
      if (header &&& 32) != 0 do
        <<count>> = bytes(file, 1)

        for <<id, size, index <- bytes(file, count * 3)>> do
          unless MapSet.member?(descriptions, {index, id}),
            do: raise(ArgumentError, "undefined method 'fit_base_type_id' for nil")

          size
        end
      else
        []
      end

    %{number: number, endian: endian, fields: fields, developer: Enum.sum(developer)}
  end

  def bytes(_file, 0), do: <<>>

  def bytes(file, size) do
    case :file.read(file, size) do
      {:ok, bytes} when byte_size(bytes) == size -> bytes
      _ -> raise ArgumentError, "Premature end of file"
    end
  end
end
