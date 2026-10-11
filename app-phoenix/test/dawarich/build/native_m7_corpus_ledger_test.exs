defmodule Dawarich.Build.NativeM7CorpusLedgerTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../../..", __DIR__)

  test "legacy frontend test retirement retains every public behavior contract" do
    historical = read("native-m7-test-retargets.json")
    integrated = read("native-m7-reconciliation.json")
    files = historical["files"]
    assert length(files) == 549
    assert Enum.count(files, & &1["historical"]) == 254
    assert Enum.sum(Enum.map(files, &length(&1["cases"]))) == 2578

    for file <- files do
      assert File.regular?(source(file["file"])), file["file"]
      assert file["fixture_policy"] != ""

      for entry <- file["cases"] do
        assert entry["old"]["name"] != ""
        assert entry["classification"] != ""
        assert entry["successor"] != nil
      end
    end

    refs = references([files, historical["feature_contracts"], historical["register_rows"]])
    renames = Map.new(integrated["renames"], &{&1["old"], &1["successors"]})
    assert map_size(renames) == length(integrated["renames"])

    for reference <- refs do
      successors = Map.get(renames, reference, [reference])
      assert successors != [], inspect(reference)

      for %{"file" => file, "name" => name} <- successors do
        assert named?(file, name), "unresolved successor #{file}:#{name}"
      end
    end

    assert Enum.sort(Map.keys(historical["planned_cleanup_successors"])) ==
             Enum.sort(integrated["pending_cleanup"])
  end

  test "reconciliation retains fixture readers and historical difference registers" do
    historical = read("native-m7-test-retargets.json")
    integrated = read("native-m7-reconciliation.json")
    assert length(historical["register_rows"]) == 127
    assert integrated["baseline_reader_count"] == 402
    assert length(integrated["legacy_reader_handoffs"]) == 13

    for row <- integrated["legacy_reader_handoffs"] do
      assert File.regular?(source(row["file"]))
      assert row["fixture_policy"] != ""
      assert row["cleanup_owner"] != ""
      assert row["disposition"] =~ "no deletion clearance"
      assert row["current_cases"] != [] or is_binary(row["module_contract"])

      assert Enum.sort(Enum.map(row["current_cases"], & &1["name"])) ==
               Enum.sort(declarations(row["file"]))

      for entry <- row["current_cases"] do
        assert named?(entry["file"], entry["name"]), entry["file"]
      end
    end

    for row <- historical["register_rows"] do
      assert File.read!(source(row["register"])) =~ row["id"]
    end

    readers = Enum.map(integrated["readers"], & &1["file"])
    assert Enum.uniq(readers) == readers
    assert length(readers) > 350

    current =
      for directory <- ~w(app-phoenix/test app-phoenix/parity spec),
          file <- Path.wildcard(Path.join(@root, "#{directory}/**/*")),
          Path.extname(file) in ~w(.ex .exs .mjs .js),
          not String.contains?(file, "/fixtures/"),
          Enum.any?(integrated["reader_markers"], &String.contains?(File.read!(file), &1)),
          do: Path.relative_to(file, @root)

    assert Enum.sort(readers) == Enum.sort(current)

    for row <- integrated["readers"] do
      text = File.read!(source(row["file"]))
      assert row["markers"] != []
      for marker <- row["markers"], do: assert(text =~ marker, row["file"])
    end

    assert integrated["fixture_disposition"] == "retain external corpus unchanged"
  end

  defp read(file) do
    @root |> Path.join("docs/phoenix/#{file}") |> File.read!() |> Jason.decode!()
  end

  defp source("T/" <> file), do: Path.join(@root, "app-phoenix/test/#{file}")
  defp source(file), do: Path.join(@root, file)

  defp declarations(file) do
    text = File.read!(source(file))

    for quote <- [~s("), "'", "`"],
        pattern = "\\btest\\s*(?:\\(\\s*)?#{quote}((?:\\\\.|[^#{quote}\\\\])*)#{quote}",
        [_, name] <- Regex.scan(Regex.compile!(pattern), text),
        do: name
  end

  defp named?(file, name) do
    normalize = &(&1 |> String.replace(~S(\"), ~s(")) |> String.replace(~S(\'), "'"))
    pattern = "\\b(?:test|it)\\s*\\(?\\s*[\"'`]#{Regex.escape(normalize.(name))}[\"'`]"

    if File.regular?(source(file)) do
      text = normalize.(File.read!(source(file)))

      generated =
        case Regex.run(~r/@test_name (.*?)\n\s*test @test_name/s, text) do
          [_, definition] -> String.contains?(definition, ~s("#{normalize.(name)}"))
          _ -> false
        end

      Regex.match?(Regex.compile!(pattern), text) or generated
    else
      false
    end
  end

  defp references(%{"file" => file, "name" => name} = map) do
    [%{"file" => file, "name" => name} | references(Map.values(map))]
  end

  defp references(map) when is_map(map), do: references(Map.values(map))
  defp references(list) when is_list(list), do: Enum.flat_map(list, &references/1)
  defp references(_), do: []
end
