defmodule DawarichWeb.CableProxy.Frame do
  @moduledoc false

  @kinds %{0 => :continuation, 1 => :text, 2 => :binary, 8 => :close, 9 => :ping, 10 => :pong}
  @opcodes Map.new(@kinds, fn {opcode, kind} -> {kind, opcode} end)

  def encode(kind, payload) do
    payload = IO.iodata_to_binary(payload)
    size = byte_size(payload)
    mask = :crypto.strong_rand_bytes(4)
    stream = binary_part(:binary.copy(mask, div(size, 4) + 1), 0, size)

    [
      <<1::1, 0::3, Map.fetch!(@opcodes, kind)::4>>,
      masked_length(size),
      mask,
      :crypto.exor(payload, stream)
    ]
  end

  def decode(buffer, frames \\ []) do
    case frame(buffer) do
      {:ok, frame, rest} -> decode(rest, [frame | frames])
      :more -> {:ok, Enum.reverse(frames), buffer}
      :error -> :error
    end
  end

  defp masked_length(size) when size < 126, do: <<1::1, size::7>>
  defp masked_length(size) when size < 65_536, do: <<1::1, 126::7, size::16>>
  defp masked_length(size), do: <<1::1, 127::7, size::64>>

  defp frame(<<_::1, rsv::3, _::4, mask::1, _::bitstring>>) when rsv != 0 or mask == 1, do: :error

  defp frame(
         <<fin::1, 0::3, opcode::4, 0::1, 127::7, size::64, payload::binary-size(size),
           rest::binary>>
       ),
       do: known(fin, opcode, payload, rest)

  defp frame(
         <<fin::1, 0::3, opcode::4, 0::1, 126::7, size::16, payload::binary-size(size),
           rest::binary>>
       ),
       do: known(fin, opcode, payload, rest)

  defp frame(<<fin::1, 0::3, opcode::4, 0::1, size::7, payload::binary-size(size), rest::binary>>)
       when size < 126,
       do: known(fin, opcode, payload, rest)

  defp frame(_buffer), do: :more

  defp known(fin, opcode, payload, rest) do
    case Map.fetch(@kinds, opcode) do
      {:ok, kind} -> {:ok, {fin == 1, kind, payload}, rest}
      :error -> :error
    end
  end
end
