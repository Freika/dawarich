defmodule DawarichWeb.A12f3aFClosureTest do
  use ExUnit.Case, async: false

  @dir Path.expand("../fixtures/imports/formats", __DIR__)

  @tag a12f3a_f23: true
  test "F23: semantic history enhanced adapter matches current Rails contract without a native-owner Rails effect" do
    assert_adapter(23, Dawarich.EnhancedImport.SemanticAdapter)
  end

  @tag a12f3a_f24: true
  test "F24: phone takeout enhanced adapter matches current Rails contract without a native-owner Rails effect" do
    assert_adapter(24, Dawarich.EnhancedImport.PhoneAdapter)
  end

  defp assert_adapter(task, adapter) do
    captures = File.read!(Path.join(@dir, "a12f3a-f#{task}.json")) |> Jason.decode!()
    root = Path.join(System.tmp_dir!(), "f-adapter-#{Ecto.UUID.generate()}")
    File.mkdir_p!(root)

    try do
      for {name, capture} <- Enum.sort(captures) do
        path = Path.join(root, "input.json")
        File.write!(path, Base.decode16!(capture["input"]["__bytes__"], case: :mixed))
        context = %{zone: capture["zone"], now: ~U[2026-01-15 23:30:00Z]}

        if error = capture["error"] do
          exception =
            if error["class"] in ["NoMethodError", "TypeError"],
              do: ArgumentError,
              else: Dawarich.Imports.JsonStream.Error

          assert_raise exception, fn ->
            adapter.reduce(path, %{id: 987_101}, context, [], &[&1 | &2])
          end
        else
          actual = adapter.reduce(path, %{id: 987_101}, context, [], &[&1 | &2])
          assert Enum.reverse(actual) == capture["rows"], name
        end
      end
    after
      File.rm_rf!(root)
    end
  end
end
