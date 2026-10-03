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
          assert {:object, pairs} = parse.()
          assert same?(Enum.map(pairs, &elem(&1, 1)), Map.values(@record["value"]))
          assert Enum.map(pairs, &elem(&1, 0)) == Map.keys(@record["value"])
        end
      end)
    end
  end

  for record <- Jason.decode!(File.read!(@compat_oracle)) do
    @record record
    test "actual Oj GeoJSON saj lexical oracle #{record["name"]}" do
      with_source(@record["input"], fn path ->
        parse = fn ->
          path
          |> JsonStream.reduce(
            [],
            fn
              {:value, ["altitude"], value, _, _}, acc -> [value | acc]
              _, acc -> acc
            end,
            fn _ -> true end
          )
          |> Enum.reverse()
        end

        case @record["saj"] do
          %{"outcome" => "error"} -> assert_raise JsonStream.Error, parse
          %{"values" => values} -> assert same?(parse.(), values)
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
    {:monitors, [process: guard]} = Process.info(pid, :monitors)
    guard_ref = Process.monitor(guard)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, :normal}
    refute File.exists?(directory)

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
    with_large_string(:discarded, fn path ->
      assert [42] ==
               JsonStream.reduce(path, [], &selected/2, &(&1 == ["selected"]),
                 max_heap_bytes: 4 * 1024 * 1024
               )
    end)
  end

  test "a retained 8MiB string costs about its own size, not a list cell per byte" do
    with_large_string(:retained, fn path ->
      assert [value] =
               JsonStream.reduce(path, [], &selected/2, &(&1 == ["selected"]),
                 mode: :compat,
                 max_heap_bytes: 48 * 1024 * 1024
               )

      assert byte_size(value) == 8 * 1024 * 1024
    end)
  end

  test "a short retained string does not pin the read buffer it came from" do
    padding = :binary.copy("p", 60_000)

    with_source(~s({"pad":"#{padding}","selected":"short"}), fn path ->
      assert ["short"] = [value] = JsonStream.reduce(path, [], &selected/2, &(&1 == ["selected"]))
      assert :binary.referenced_byte_size(value) < 1024
    end)
  end

  test "a parse over its heap cap fails the reduce with a memory error and leaves the caller running" do
    with_large_string(:retained, fn path ->
      error =
        assert_raise JsonStream.Error, fn ->
          JsonStream.reduce(path, [], &selected/2, &(&1 == ["selected"]),
            max_heap_bytes: 4 * 1024 * 1024
          )
        end

      assert error.reason == :memory
      assert error.message == "JSON document needs more than 4 MiB of memory"
    end)
  end

  test "nesting is capped at 10000 levels" do
    deep = fn n -> String.duplicate("[", n) <> String.duplicate("]", n) end
    with_source(deep.(10_000), fn path -> assert :ok == JsonStream.reduce(path, :ok, &keep/2) end)

    with_source(deep.(10_001), fn path ->
      error = assert_raise JsonStream.Error, fn -> JsonStream.reduce(path, :ok, &keep/2) end
      assert error.reason == :depth
    end)
  end

  @tag :tmp_dir
  test "retained object members are collected in linear time", %{tmp_dir: dir} do
    assert reductions(dir, 20_000) < 8 * reductions(dir, 5_000)
  end

  @tag :tmp_dir
  test "a callback error stops the parser and reaches the caller", %{tmp_dir: dir} do
    path = Path.join(dir, "list.json")
    File.write!(path, "[" <> Enum.map_join(1..1000, ",", &Integer.to_string/1) <> "]")

    assert_raise RuntimeError, "callback failed", fn ->
      JsonStream.reduce(path, nil, fn
        {:value, [0], _, _, _}, _ ->
          {:monitors, [process: parser]} = Process.info(self(), :monitors)
          send(self(), {:parser, parser})
          raise "callback failed"

        _, acc ->
          acc
      end)
    end

    assert_received {:parser, parser}
    ref = Process.monitor(parser)
    assert_receive {:DOWN, ^ref, :process, ^parser, reason} when reason in [:killed, :noproc]
  end

  test "a killed spool guard does not leave the owner waiting" do
    {:monitored_by, before} = Process.info(self(), :monitored_by)

    Spool.with_directory(%{}, fn directory ->
      send(self(), {:directory, directory})
      {:monitored_by, now} = Process.info(self(), :monitored_by)
      [guard] = now -- before
      Process.exit(guard, :kill)
    end)

    assert_received {:directory, directory}
    refute File.exists?(directory)
  end

  defp same?(actual, expected) when is_list(actual) and is_list(expected),
    do: length(actual) == length(expected) and Enum.all?(Enum.zip(actual, expected), &same?/1)

  defp same?({actual, %{"scrubbed" => text}}), do: actual == text

  defp same?({actual, expected}) when is_float(expected),
    do: is_float(actual) and actual == expected

  defp same?({actual, expected}) when is_integer(expected),
    do: is_integer(actual) and actual == expected

  defp same?({actual, expected}), do: actual == expected

  defp selected({:value, ["selected"], value, _, _}, acc), do: [value | acc]
  defp selected(_, acc), do: acc
  defp keep(_, acc), do: acc

  defp reductions(dir, n) do
    path = Path.join(dir, "object-#{n}.json")
    File.write!(path, "{" <> Enum.map_join(1..n, ",", &~s("k#{&1}":#{&1})) <> "}")

    {_parser, count} =
      JsonStream.reduce(
        path,
        nil,
        fn
          _, nil ->
            {:monitors, [process: parser]} = Process.info(self(), :monitors)
            {parser, 0}

          _, {parser, count} ->
            case Process.info(parser, :reductions) do
              {:reductions, latest} -> {parser, latest}
              nil -> {parser, count}
            end
        end,
        fn _ -> true end
      )

    count
  end

  defp with_large_string(kind, fun) do
    Spool.with_directory(%{}, fn directory ->
      path = Path.join(directory, "source")
      f = Spool.open!(path)
      IO.binwrite(f, if(kind == :discarded, do: ~s({"unknown":"), else: ~s({"selected":")))
      block = :binary.copy("x", 65536)
      Enum.each(1..128, fn _ -> IO.binwrite(f, block) end)
      IO.binwrite(f, if(kind == :discarded, do: ~s(","selected":42}), else: ~s("})))
      File.close(f)
      fun.(path)
    end)
  end

  defp with_source(json, fun) do
    Spool.with_directory(%{}, fn directory ->
      path = Path.join(directory, "source")
      File.write!(path, json)
      fun.(path)
    end)
  end
end
