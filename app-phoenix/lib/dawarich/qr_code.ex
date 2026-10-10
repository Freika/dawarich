defmodule Dawarich.QrCode do
  @moduledoc false

  import Bitwise

  @tables Path.expand("../../priv/qr_tables.json", __DIR__)
  @external_resource @tables
  @json @tables |> File.read!() |> Jason.decode!()
  @max_bits @json["max_bits_h"]
  @rs_blocks @json["rs_blocks_h"]
  @exp Enum.reduce(8..255, Enum.map(0..7, &bsl(1, &1)), fn i, acc ->
         acc ++ [Enum.reduce([4, 5, 6, 8], 0, &bxor(&2, Enum.at(acc, i - &1)))]
       end)
       |> List.to_tuple()
  @log for(i <- 0..254, into: %{}, do: {elem(@exp, i), i})

  def modules(data) when is_binary(data) do
    if data =~ ~r/\A[0-9A-Z $%*+\-.\/:]*\z/,
      do: raise(ArgumentError, "only byte-mode data is supported")

    version = version(byte_size(data), 1)
    Dawarich.QrMatrix.build(version, codewords(data, version))
  end

  defp version(_bytes, 41), do: raise(ArgumentError, "data too long for a QR code")

  defp version(bytes, version) do
    if 4 + header(version) + bytes * 8 < Enum.at(@max_bits, version - 1),
      do: version,
      else: version(bytes, version + 1)
  end

  defp header(version) when version < 10, do: 8
  defp header(_version), do: 16

  defp codewords(data, version) do
    blocks =
      @rs_blocks
      |> Enum.at(version - 1)
      |> Enum.chunk_every(3)
      |> Enum.flat_map(fn [count, total, data] -> List.duplicate({total, data}, count) end)

    max = blocks |> Enum.map(&elem(&1, 1)) |> Enum.sum() |> Kernel.*(8)
    bits = <<4::4, byte_size(data)::size(header(version)), data::binary>>
    bits = if bit_size(bits) + 4 > max, do: bits, else: <<bits::bitstring, 0::4>>
    bits = <<bits::bitstring, 0::size(rem(8 - rem(bit_size(bits), 8), 8))>>
    bytes = :binary.bin_to_list(bits) ++ pads(max - bit_size(bits), [0xEC, 0x11])

    {dc, ec, []} =
      Enum.reduce(blocks, {[], [], bytes}, fn {total, count}, {dc, ec, rest} ->
        {block, rest} = Enum.split(rest, count)
        {[block | dc], [remainder(block, total - count) | ec], rest}
      end)

    interleave(Enum.reverse(dc)) ++ interleave(Enum.reverse(ec))
  end

  defp pads(bits, _pattern) when bits <= 0, do: []
  defp pads(bits, [a, b]) when bits <= 8, do: [a | pads(bits - 8, [b, a])]
  defp pads(bits, [a, b]), do: [a, b | pads(bits - 16, [a, b])]

  defp interleave(blocks) do
    longest = blocks |> Enum.map(&length/1) |> Enum.max()
    for i <- 0..(longest - 1), block <- blocks, i < length(block), do: Enum.at(block, i)
  end

  defp remainder(data, ec) do
    generator = Enum.reduce(0..(ec - 1), [1], fn i, acc -> multiply(acc, [1, gexp(i)]) end)
    divide(data ++ List.duplicate(0, ec), generator, length(data))
  end

  defp divide(poly, _generator, 0), do: poly
  defp divide([0 | rest], generator, steps), do: divide(rest, generator, steps - 1)

  defp divide([lead | _] = poly, generator, steps) do
    ratio = @log[lead] - @log[hd(generator)]
    scaled = Enum.map(generator, &gexp(@log[&1] + ratio))
    {head, tail} = Enum.split(poly, length(generator))
    [0 | rest] = Enum.zip_with(head, scaled, &bxor/2)
    divide(rest ++ tail, generator, steps - 1)
  end

  defp multiply(a, b) do
    empty = List.duplicate(0, length(a) + length(b) - 1)

    for {x, i} <- Enum.with_index(a), {y, j} <- Enum.with_index(b), reduce: empty do
      acc -> List.update_at(acc, i + j, &bxor(&1, gexp(@log[x] + @log[y])))
    end
  end

  defp gexp(n), do: elem(@exp, Integer.mod(n, 255))
end
