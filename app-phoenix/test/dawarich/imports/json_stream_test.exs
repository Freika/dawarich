defmodule Dawarich.Imports.JsonStreamTest do
  use ExUnit.Case, async: false
  import Bitwise
  alias Dawarich.Imports.JsonStream
  alias Dawarich.Imports.JsonStream.Spool

  test "unknown nested values are validated rather than skipped lexically" do
    for json <- [
          ~s({"unknown":[1e+z,true]}),
          ~s({"unknown":"\\uZZZZ"}),
          ~s({"unknown":[0x1]}),
          ~s({"unknown":{"bad":}})
        ] do
      with_source(json, fn path ->
        assert_raise JsonStream.Error, fn -> JsonStream.reduce(path, 0, fn _, n -> n + 1 end) end
      end)
    end
  end

  test "nested and duplicate retained object keys preserve Ruby insertion order" do
    json = ~s({"selected":{"z":1,"a":2,"z":3},"unknown":[{"more":[1,2,3]}]})

    with_source(json, fn path ->
      actual =
        JsonStream.reduce(
          path,
          [],
          fn
            {:value, ["selected"], v, _, _}, acc -> [v | acc]
            _, acc -> acc
          end,
          fn path -> path == ["selected"] end
        )

      assert actual == [{:object, [{"z", 3}, {"a", 2}]}]
    end)
  end

  test "compat mode preserves independent FileLoader Oj.load syntax and Unicode" do
    for bad <- ["", "{} {}", "[01]", "[+1]", "[1.]", "[1e+]", ~s({"unknown":"\\uD800"})] do
      with_source(bad, fn path ->
        assert_raise JsonStream.Error, fn ->
          JsonStream.reduce(path, 0, fn _, n -> n + 1 end, fn _ -> true end, mode: :compat)
        end
      end)
    end

    with_source(~s({"selected":"\\uD83D\\uDEF0","number":NaN}), fn path ->
      result =
        JsonStream.reduce(
          path,
          [],
          fn
            {:value, ["selected"], v, _, _}, acc -> [v | acc]
            {:value, ["number"], v, _, _}, acc -> [v | acc]
            _, acc -> acc
          end,
          fn _ -> true end,
          mode: :compat
        )

      assert result == [:nan, "🛰"]
    end)
  end

  @compat_oracle Path.expand("../../fixtures/imports/geojson/compat-lexical.json", __DIR__)
  for record <- Jason.decode!(File.read!(@compat_oracle)) do
    @record record
    test "actual Oj compat lexical oracle #{record["name"]}" do
      with_source(@record["input"], fn path ->
        parse = fn ->
          JsonStream.reduce(
            path,
            nil,
            fn
              {:value, [], value, _, _}, _ -> value
              _, acc -> acc
            end,
            fn _ -> true end,
            mode: :compat
          )
        end

        if @record["outcome"] == "error" do
          error = assert_raise JsonStream.Error, parse
          expected = if @record["error"] == "Oj::ParseError", do: :invalid_float, else: :syntax
          assert error.reason == expected
        else
          assert parse.() == {:object, Enum.to_list(@record["value"])}
        end
      end)
    end
  end

  test "actual closed IO device errors abort private spool writes" do
    Spool.with_directory(%{}, fn directory ->
      file = Spool.open!(Path.join(directory, "rows"))
      :ok = File.close(file)
      assert_raise File.Error, fn -> Spool.write!(file, %{never_persisted: true}) end
    end)
  end

  test "private spool permissions, exception cleanup and owner kill cleanup" do
    parent = self()

    pid =
      spawn(fn ->
        Spool.with_directory(%{}, fn directory ->
          f = Spool.open!(Path.join(directory, "rows"))

          try do
            Spool.write!(f, %{private: "synthetic"})
            send(parent, {:private_directory, directory})
            receive do: (:never -> :ok)
          after
            File.close(f)
          end
        end)
      end)

    assert_receive {:private_directory, directory}, 2000
    assert band(File.stat!(directory).mode, 0o777) == 0o700
    assert band(File.stat!(Path.join(directory, "rows")).mode, 0o777) == 0o600
    Process.exit(pid, :kill)
    eventually(fn -> not File.exists?(directory) end)

    assert_raise RuntimeError, fn ->
      Spool.with_directory(%{}, fn directory ->
        send(self(), {:exception_directory, directory})
        raise "actual interrupted consumer"
      end)
    end

    assert_receive {:exception_directory, directory}
    refute File.exists?(directory)
  end

  test "discarded 8MiB unknown string never becomes a retained DOM" do
    Spool.with_directory(%{}, fn directory ->
      path = Path.join(directory, "source")
      f = Spool.open!(path)
      IO.binwrite(f, ~s({"unknown":"))
      block = :binary.copy("x", 65536)
      Enum.each(1..128, fn _ -> IO.binwrite(f, block) end)
      IO.binwrite(f, ~s(","selected":42}))
      File.close(f)
      parent = self()

      pid =
        spawn(fn ->
          result =
            JsonStream.reduce(
              path,
              [],
              fn
                {:value, ["selected"], v, _, _}, acc -> [v | acc]
                _, acc -> acc
              end,
              fn path -> path == ["selected"] end
            )

          send(parent, {:stream_result, result})
        end)

      peak = monitor_memory(pid, 0)
      assert_receive {:stream_result, [42]}, 2000
      assert peak < 8 * 1024 * 1024
    end)
  end

  defp monitor_memory(pid, peak) do
    case Process.info(pid, :memory) do
      nil ->
        peak

      {:memory, bytes} ->
        Process.sleep(10)
        monitor_memory(pid, max(bytes, peak))
    end
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, n) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(10)
          eventually(fun, n - 1)
        )
  end

  defp with_source(json, fun) do
    Spool.with_directory(%{}, fn directory ->
      path = Path.join(directory, "source")
      File.write!(path, json)
      fun.(path)
    end)
  end
end
