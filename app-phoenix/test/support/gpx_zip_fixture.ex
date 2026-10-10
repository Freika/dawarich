defmodule Dawarich.GpxZipFixture do
  @moduledoc false
  import Bitwise

  def write!(path, entries, opts \\ []) do
    {files, central, offset} =
      Enum.reduce(entries, {[], [], 0}, fn {name, content, entry_opts},
                                           {files, central, offset} ->
        method = Keyword.get(entry_opts, :method, 8)
        data = if method == 0, do: content, else: :zlib.zip(content)
        data = Keyword.get(entry_opts, :compressed_data, data)
        crc = Keyword.get(entry_opts, :crc, :erlang.crc32(content))
        size = Keyword.get(entry_opts, :size, byte_size(content))
        flags = Keyword.get(entry_opts, :flags, 0)
        descriptor? = band(flags, 8) != 0
        local_crc = if descriptor?, do: 0, else: crc
        local_size = if descriptor?, do: 0, else: size
        local_compressed = if descriptor?, do: 0, else: byte_size(data)
        local_name = Keyword.get(entry_opts, :local_name, name)

        header =
          <<0x04034B50::little-32, 20::little-16, flags::little-16, method::little-16, 0::32,
            local_crc::little-32, local_compressed::little-32, local_size::little-32,
            byte_size(local_name)::little-16, 0::16>> <> local_name

        trailer =
          if descriptor?,
            do:
              <<0x08074B50::little-32, crc::little-32, byte_size(data)::little-32,
                size::little-32>>,
            else: <<>>

        blob = header <> data <> trailer
        attrs = Keyword.get(entry_opts, :attrs, 0o100644 <<< 16)

        cd =
          <<0x02014B50::little-32, 0x0314::little-16, 20::little-16, flags::little-16,
            method::little-16, 0::32, crc::little-32, byte_size(data)::little-32, size::little-32,
            byte_size(name)::little-16, 0::16, 0::16, 0::16, 0::16, attrs::little-32,
            offset::little-32>> <> name

        {[blob | files], [cd | central], offset + byte_size(blob)}
      end)

    central = central |> Enum.reverse() |> IO.iodata_to_binary()
    count = length(entries)
    comment = Keyword.get(opts, :comment, <<>>)

    eocd =
      <<0x06054B50::little-32, 0::32, count::little-16, count::little-16,
        byte_size(central)::little-32, offset::little-32, byte_size(comment)::little-16>> <>
        comment

    File.write!(path, [Enum.reverse(files), central, eocd])
    path
  end
end
