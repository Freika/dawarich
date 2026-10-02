ExUnit.start()

defmodule Dawarich.RailsCache.WireTest do
  use ExUnit.Case, async: true
  alias Dawarich.RailsCache.{Marshal, Wire}

  @fixtures Path.expand("../../fixtures/rails_cache", __DIR__)

  test "reads actual Rails8.1 Redis entries including compressed AR and fragments" do
    for file <- Path.wildcard(Path.join(@fixtures, "*.wire")),
        not String.contains?(file, "raw-counter") do
      assert {:ok, %{value: _, expires_at: expires}} = Wire.decode(File.read!(file))
      assert is_float(expires)
    end

    assert {:ok, %{value: 81}} = read("integer")
    assert {:ok, %{value: -901}} = read("negative")
    assert {:ok, %{value: value}} = read("bignum")
    assert value == Integer.pow(2, 90)
    assert {:ok, %{value: 1.25}} = read("float")
    assert {:ok, %{value: nil}} = read("nil")
    assert {:ok, %{value: false}} = read("false")
    assert {:ok, %{value: true}} = read("true")
    assert {:ok, %{value: "Berlin — 東京"}} = read("utf8")
  end

  test "native encodings round trip without constructing Ruby classes" do
    for value <- [
          nil,
          true,
          false,
          0,
          81,
          -901,
          Integer.pow(2, 90),
          1.25,
          "Berlin — 東京",
          [1, nil, false],
          %{"plan" => "pro"}
        ] do
      assert {:ok, ^value} = value |> Marshal.encode() |> Marshal.decode()

      assert {:ok, %{value: ^value, version: "v1"}} =
               value |> Wire.encode(expires_at: 2_000_000_000.125, version: "v1") |> Wire.decode()
    end
  end

  test "malformed headers and Ruby records remain explicit cache decoding failures" do
    for bytes <- [
          <<>>,
          <<0, 17>>,
          <<4, 8, ?i>>,
          <<0, 17, 0, 0::little-float-64, -1::little-signed-32>>
        ] do
      assert {:error, _} = Wire.decode(bytes)
    end
  end

  defp read(name), do: File.read!(Path.join(@fixtures, "codec-#{name}.wire")) |> Wire.decode()
end
