defmodule Dawarich.UserData.Paths do
  @moduledoc false

  def sanitize(name) do
    name = String.replace(name, ~r/\A[\/\\]+/, "")
    if String.contains?(name, ".."), do: nil, else: name
  end

  def relative(base, name) do
    if blank?(name) do
      nil
    else
      base = Path.expand(base)
      expanded = Path.expand(to_string(name), base)

      if expanded == base or String.starts_with?(expanded, base <> "/"),
        do: Path.join(base, to_string(name))
    end
  end

  def attachment(base, name) do
    unless blank?(name) do
      basename = name |> to_string() |> Path.basename()
      if basename not in ["", ".", ".."], do: Path.join(base, basename)
    end
  end

  defp blank?(value) when value in [nil, false], do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
