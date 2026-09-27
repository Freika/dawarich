defmodule DawarichWeb.Translate do
  @moduledoc false

  import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

  def t(locale, key, bindings) do
    bindings = Map.new(bindings, fn {name, value} -> {to_string(name), value} end)
    html? = String.ends_with?(key, "_html") or String.ends_with?(key, ".html")

    case Dawarich.I18n.t(locale, key, if(html?, do: escape(bindings), else: bindings)) do
      {:ok, text} when html? -> {:safe, text}
      {:ok, text} -> text
      {:error, {:reserved_interpolation_key, reserved}} -> raise_reserved(locale, key, reserved)
      _ -> missing(locale, key)
    end
  end

  defp escape(bindings) do
    Map.new(bindings, fn
      {"count", value} when is_number(value) -> {"count", value}
      {name, value} -> {name, value |> html_escape() |> safe_to_string()}
    end)
  end

  defp raise_reserved(locale, key, reserved),
    do: raise(ArgumentError, "reserved key #{reserved} used in #{locale}.#{key}")

  defp missing(locale, key) do
    label = key |> String.split(".") |> List.last() |> titleize()
    title = "translation missing: #{locale}.#{key}"

    {:safe,
     ~s(<span class="translation_missing" title="#{safe_to_string(html_escape(title))}">#{safe_to_string(html_escape(label))}</span>)}
  end

  defp titleize(word) do
    underscored = underscore(word)
    spaced = underscored |> String.replace("_", " ") |> String.trim_leading()

    id_stripped =
      if String.ends_with?(underscored, "_id"),
        do: String.replace_suffix(spaced, " id", ""),
        else: spaced

    downcased = Regex.replace(~r/[\p{L}\p{N}]+/u, id_stripped, &String.downcase/1)
    humanized = Regex.replace(~r/\A[\p{L}]/u, downcased, &String.upcase/1)

    Regex.replace(~r/\b(?<!\w['’`()])[a-z]/u, humanized, &String.upcase/1)
  end

  defp underscore(word) do
    word
    |> String.replace("::", "/")
    |> then(&Regex.replace(~r/(?<=[A-Z])(?=[A-Z][a-z])|(?<=[a-z0-9])(?=[A-Z])/, &1, "_"))
    |> String.replace("-", "_")
    |> String.downcase()
  end
end
