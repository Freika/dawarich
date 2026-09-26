defmodule Dawarich.ReleaseMigrations.EncryptedColumnsTest do
  use ExUnit.Case, async: true

  alias Dawarich.RailsTree

  @list "scripts/schema_parity/encrypted_columns.tsv"
  @otp_secret_column ~s(ALTER TABLE "users" ADD "otp_secret" character varying;)

  test "encrypted_columns.tsv lists exactly the attributes the Rails models encrypt" do
    listed =
      @list
      |> RailsTree.read()
      |> String.split("\n", trim: true)
      |> Enum.map(&List.to_tuple(String.split(&1, "\t")))

    assert listed == Enum.sort(listed)
    assert Enum.sort(declared()) == listed
  end

  test "every encrypts declaration uses the default scheme Dawarich.ActiveRecordEncryption implements" do
    for {path, declaration} <- declarations() do
      assert declaration =~ ~r/\A:\w+(\s*,\s*:\w+)*\z/,
             "#{path}: encrypts #{declaration} has options the Phoenix module does not implement"
    end

    for path <- RailsTree.wildcard("{app,config,lib}/**/*.rb") do
      refute RailsTree.read(path) =~ "otp_encrypted_attribute_options",
             "#{path} passes options to devise-two-factor's encrypts :otp_secret"
    end
  end

  test "no release migration writes users.otp_secret, which only devise-two-factor encrypts" do
    assert {"users", "otp_secret"} in declared()

    for path <- RailsTree.wildcard("app-phoenix/lib/dawarich/release_migrations/**/*.ex") do
      refute path |> RailsTree.read() |> String.replace(@otp_secret_column, "") =~ "otp_secret",
             "#{path} touches users.otp_secret beyond adding the column"
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
        source = RailsTree.read(path),
        declaration <- explicit(source) ++ two_factor(source),
        do: {path, declaration}
  end

  defp explicit(source) do
    for [declaration] <-
          Regex.scan(~r/^\s*encrypts(?:\s+|\s*\(\s*)(.+?)\s*\)?\s*$/m, source,
            capture: :all_but_first
          ),
        do: declaration
  end

  defp two_factor(source) do
    if source =~ ~r/:two_factor_authenticatable\b/, do: [":otp_secret"], else: []
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
