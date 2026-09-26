defmodule DawarichWeb.CableProxy.FrameTest do
  use ExUnit.Case, async: true

  alias DawarichWeb.CableProxy.Frame

  test "Puma's frames decode at every length, and an incomplete frame waits" do
    small = :binary.copy("a", 125)
    medium = :binary.copy("b", 126)
    large = :binary.copy("c", 70_000)
    partial = <<1::1, 0::3, 1::4, 0::1, 5::7, "he">>

    buffer =
      <<1::1, 0::3, 1::4, 0::1, 125::7, small::binary, 0::1, 0::3, 2::4, 0::1, 126::7, 126::16,
        medium::binary, 1::1, 0::3, 0::4, 0::1, 127::7, 70_000::64, large::binary,
        partial::binary>>

    assert Frame.decode(buffer) ==
             {:ok, [{true, :text, small}, {false, :binary, medium}, {true, :continuation, large}],
              partial}
  end

  test "masked, reserved-bit and unknown-opcode frames from Puma are refused" do
    assert Frame.decode(<<1::1, 0::3, 1::4, 1::1, 1::7, 0::32, "x">>) == :error
    assert Frame.decode(<<1::1, 4::3, 1::4, 0::1, 1::7, "x">>) == :error
    assert Frame.decode(<<1::1, 0::3, 3::4, 0::1, 1::7, "x">>) == :error
  end

  test "control frames from Puma over 125 bytes or fragmented are refused" do
    ping = :binary.copy("p", 126)
    assert Frame.decode(<<1::1, 0::3, 9::4, 0::1, 126::7, 126::16, ping::binary>>) == :error
    assert Frame.decode(<<0::1, 0::3, 8::4, 0::1, 2::7, 1000::16>>) == :error

    assert Frame.decode(<<1::1, 0::3, 10::4, 0::1, 125::7, :binary.copy("p", 125)::binary>>) ==
             {:ok, [{true, :pong, :binary.copy("p", 125)}], ""}
  end

  test "frames to Puma are masked and carry their length" do
    for size <- [0, 125, 126, 65_536] do
      payload = :binary.copy("z", size)

      <<1::1, 0::3, 2::4, 1::1, rest::bitstring>> =
        IO.iodata_to_binary(Frame.encode(:binary, payload))

      {length, <<mask::binary-size(4), masked::binary>>} =
        case rest do
          <<126::7, n::16, tail::binary>> -> {n, tail}
          <<127::7, n::64, tail::binary>> -> {n, tail}
          <<n::7, tail::binary>> -> {n, tail}
        end

      assert length == size

      assert :crypto.exor(masked, binary_part(:binary.copy(mask, div(size, 4) + 1), 0, size)) ==
               payload
    end
  end
end
