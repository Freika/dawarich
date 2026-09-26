defmodule Dawarich.ReleaseMigrations.EncryptedColumnsTest do
  use ExUnit.Case, async: true

  alias Dawarich.RailsTree

  @list "scripts/schema_parity/encrypted_columns.tsv"

  test "encrypted_columns.tsv lists exactly the attributes the Rails models encrypt" do
    listed =
      @list
      |> RailsTree.read()
      |> String.split("\n", trim: true)
      |> Enum.map(&List.to_tuple(String.split(&1, "\t")))

    assert listed == Enum.sort(listed)
    assert Enum.sort(declared()) == listed
  end

  test "every table in encrypted_columns.tsv is one the release migrations touch" do
    sources =
      "app-phoenix/lib/dawarich/release_migrations/**/*.ex"
      |> RailsTree.wildcard()
      |> Enum.map_join("\n", &RailsTree.read/1)

    for {table, _column} <- declared() do
      assert sources =~ ~r/\b#{table}\b/, "no release migration touches #{table}"
    end
  end

  test "every encrypts declaration uses the default scheme Dawarich.ActiveRecordEncryption implements" do
    for {path, declaration} <- declarations() do
      assert declaration =~ ~r/\A:\w+(\s*,\s*:\w+)*\z/,
             "#{path}: encrypts #{declaration} has options the Phoenix module does not implement"
    end
  end

  defp declared do
    for {path, declaration} <- declarations(),
        [attribute] <- Regex.scan(~r/:(\w+)/, declaration, capture: :all_but_first) do
      {table(path), attribute}
    end
  end

  defp declarations do
    for path <- RailsTree.wildcard("app/models/**/*.rb"),
        [declaration] <-
          Regex.scan(~r/^\s*encrypts\s+(.+?)\s*$/m, RailsTree.read(path), capture: :all_but_first),
        do: {path, declaration}
  end

  defp table(path) do
    source = RailsTree.read(path)

    case Regex.run(~r/^\s*self\.table_name\s*=\s*['"](\w+)['"]/m, source) do
      [_, table] ->
        table

      nil ->
        [_, class] = Regex.run(~r/^\s*class\s+(?:\w+::)*(\w+)\s*</m, source)
        class |> Macro.underscore() |> pluralize()
    end
  end

  defp pluralize(name) do
    cond do
      name =~ ~r/[^aeiou]y\z/ -> String.replace_suffix(name, "y", "ies")
      name =~ ~r/(s|x|z|ch|sh)\z/ -> name <> "es"
      true -> name <> "s"
    end
  end
end
