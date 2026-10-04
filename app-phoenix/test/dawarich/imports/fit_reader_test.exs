defmodule Dawarich.Imports.FitReaderTest do
  use ExUnit.Case, async: false
  alias Dawarich.Imports.Fit.Reader
  alias Dawarich.Test.NormalFormats
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)

  test "fit definition endian replacement and compressed times match fit4ruby" do
    for name <- ~w(standard flat endian compressed developer sports header12), do: run(name)
  end

  test "fit truncated data CRC and invalid sentinels match oracle" do
    for name <- ~w(truncated header_crc data_crc invalid), do: run(name)
  end

  defp run(name) do
    c =
      @dir
      |> Path.join("fit_reader_#{name}.json")
      |> File.read!()
      |> Jason.decode!()
      |> NormalFormats.decode()

    input = Path.join(@dir, c["input"])
    key = make_ref()
    Process.put(key, [])

    callback = fn record, acc ->
      Process.put(key, [record | Process.get(key)])
      [record | acc]
    end

    try do
      if c["error"] do
        assert_raise ArgumentError, c["error"]["message"], fn ->
          Reader.reduce(input, [], callback)
        end
      else
        assert Reader.reduce(input, [], callback) |> Enum.reverse() == c["records"]
      end

      assert Process.get(key) |> Enum.reverse() == c["records"]
    after
      Process.delete(key)
    end
  end
end
