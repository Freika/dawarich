defmodule Dawarich.Imports.KmlTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.Kml
  alias Dawarich.Test.{NormalFormats, NormalFormatsAssertions}
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)

  defmodule FullDevice do
    def write(_, _), do: {:error, :enospc}
    def close(nil), do: :ok
    def close(io), do: File.close(io)
  end

  @tag :tmp_dir
  test "KML close flush exhaustion preserves the spool write error", %{tmp_dir: dir} do
    alias Dawarich.Imports.Kml.Handler

    error =
      assert_raise File.Error, fn ->
        Handler.with_state(dir, fn state ->
          state = put_in(state.indexes.placemark, faulted_index(state.indexes.placemark))
          state = Handler.event({:startElement, [], ~c"Placemark", {[], []}, []}, nil, state)
          Handler.event({:endElement, [], [], []}, nil, state)
        end)
      end

    assert error.reason == :enospc
    assert error.action == "write"
    assert error.path == "private JSON spool"
  end

  @tag :tmp_dir
  test "KML index close failures preserve the primary parse error", %{tmp_dir: dir} do
    alias Dawarich.Imports.Kml.Handler

    assert_raise ArgumentError, "primary parse error", fn ->
      Handler.with_state(dir, fn state ->
        case state.indexes.placemark do
          {:file_descriptor, :raw_file_io_delayed, _} = io ->
            io = faulted_index(io)
            :ok = :file.write(io, "pending index bytes")

          _ ->
            :ok
        end

        raise ArgumentError, "primary parse error"
      end)
    end
  end

  defp faulted_index({:file_descriptor, :raw_file_io_delayed, %{pid: pid}} = io) do
    :sys.replace_state(pid, fn {status, data} ->
      {status, %{data | handle: {:file_descriptor, FullDevice, data.handle}}}
    end)

    io
  end

  defp faulted_index(_), do: {:file_descriptor, FullDevice, nil}

  @tag :tmp_dir
  test "KML spool failures occur on write rather than a delayed close flush", %{tmp_dir: dir} do
    alias Dawarich.Imports.Kml.Handler
    alias Dawarich.Imports.JsonStream.Spool

    Handler.with_state(dir, fn state ->
      for io <- Map.values(state.indexes),
          do: assert(match?({:file_descriptor, :prim_file, _}, io))

      state = Handler.event({:startElement, [], ~c"Placemark", {[], []}, []}, nil, state)

      state =
        Handler.event(
          {:characters, String.to_charlist(String.duplicate("x", 65_537))},
          nil,
          state
        )

      [capture] = state.captures
      assert {:file_descriptor, :prim_file, _} = capture.io
      :ok = File.close(capture.io)
      error = assert_raise File.Error, fn -> Spool.write!(capture.io, :unwritten) end
      assert error.action == "write"
      assert error.path == "private JSON spool"
    end)
  end

  @tag :tmp_dir
  test "small KML captures stay inline and large captures spill without losing events", %{
    tmp_dir: dir
  } do
    alias Dawarich.Imports.Kml.Handler
    alias Dawarich.Imports.JsonStream.Spool

    Handler.with_state(dir, fn state ->
      state = Handler.event({:startElement, [], ~c"Placemark", {[], []}, []}, nil, state)
      state = Handler.event({:characters, ~c"small"}, nil, state)
      state = Handler.event({:endElement, [], [], []}, nil, state)
      assert Path.wildcard(Path.join(dir, "object-*")) == []

      state = Handler.event({:startElement, [], ~c"Placemark", {[], []}, []}, nil, state)

      state =
        Handler.event(
          {:characters, String.to_charlist(String.duplicate("x", 65_537))},
          nil,
          state
        )

      Handler.event({:endElement, [], [], []}, nil, state)
    end)

    [small, large] = Enum.to_list(Spool.stream(Path.join(dir, "placemark"), [:raw]))
    assert [{:start, _}, {:text, _, "small"}, {:end, _}] = small
    assert is_binary(large)
    assert [{:start, _}, {:text, _, text}, {:end, _}] = Enum.to_list(Spool.stream(large, [:raw]))
    assert text == String.duplicate("x", 65_537)
  end

  test "kml interpolation namespaces and track pairing equal Rails" do
    for path <- Path.wildcard(Path.join(@dir, "kml_import_*.json")),
        not String.ends_with?(path, ".input.json"),
        not String.contains?(path, ["malformed", "bad_tail"]) do
      Dawarich.JobsCase.reset!(ScratchRepo)
      Dawarich.Ingest.Sources.forget()
      c = NormalFormats.seed!(Path.basename(path, ".json"), ScratchRepo)
      c = %{c | context: %{c.context | altitude_decimal?: c.expected["legacy"] != true}}

      if c.expected["legacy"] do
        assert {:error, :legacy_checked} =
                 ScratchRepo.transaction(fn ->
                   ScratchRepo.query!(
                     "ALTER TABLE points DROP COLUMN source_id, DROP COLUMN altitude_decimal"
                   )

                   Dawarich.Ingest.Sources.forget()
                   run(c)
                   ScratchRepo.rollback(:legacy_checked)
                 end)
      else
        run(c)
      end
    end
  end

  test "kml malformed XML produces no persisted points" do
    for name <- ["kml_import_malformed", "kml_import_bad_tail"] do
      Dawarich.JobsCase.reset!(ScratchRepo)
      c = NormalFormats.seed!(name, ScratchRepo)
      assert c.expected["error"]

      error =
        try do
          Kml.call(c.path, c.import, c.context)
          nil
        rescue
          e in ArgumentError -> e
        end

      NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
      assert %ArgumentError{} = error
    end
  end

  test "kml external entities never read an external file" do
    c = NormalFormats.seed!("kml_import_empty", ScratchRepo)
    dir = Path.join(System.tmp_dir!(), "kml-entity-#{System.unique_integer([:positive])}")
    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    marker = Path.join(dir, "external.dtd")
    input = Path.join(dir, "external.kml")
    File.write!(marker, "EXTERNAL_FILE_MARKER")
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    on_exit(fn -> :gen_tcp.close(listener) end)
    {:ok, port} = :inet.port(listener)

    for uri <- ["file://#{marker}", "http://127.0.0.1:#{port}/external.dtd"] do
      File.write!(input, "<!DOCTYPE kml SYSTEM \"#{uri}\"><kml/>")

      assert_raise ArgumentError, ~r/DTD is not allowed/, fn ->
        Kml.call(input, c.import, c.context)
      end

      NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
    end

    assert {:error, :timeout} = :gen_tcp.accept(listener, 0)
  end

  defp run(c) do
    if c.expected["error"] do
      assert_raise ArgumentError, fn -> Kml.call(c.path, c.import, c.context) end
    else
      assert :ok = Kml.call(c.path, c.import, c.context)
    end

    NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
  end
end
