defmodule Dawarich.Test.NativeExportCorpus do
  @moduledoc false
  import ExUnit.Assertions

  def assert_page(html, fixture, opts \\ []) do
    native =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("[data-testid=native-exports-root] #exports")

    expected = fixture |> LazyHTML.from_fragment() |> LazyHTML.query("#exports")
    assert Enum.count(native) == 1
    assert words(native) == words(expected)
    if Keyword.get(opts, :fields, true), do: assert(fields(native) == fields(expected))
    assert reads(native) == reads(expected)
  end

  defp words(doc),
    do: doc |> LazyHTML.to_tree() |> texts() |> Enum.join(" ") |> String.split() |> Enum.join(" ")

  defp texts(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &texts/1)

  defp texts({"input", attrs, _}) do
    if {"type", "submit"} in attrs, do: [List.keyfind(attrs, "value", 0) |> elem(1)], else: []
  end

  defp texts({tag, _, children}) when tag not in ["script", "style"], do: texts(children)
  defp texts(text) when is_binary(text), do: [text]
  defp texts(_), do: []

  defp fields(doc) do
    doc
    |> LazyHTML.query("input, select, option")
    |> Enum.map(fn node ->
      attrs =
        for key <- ~w(type name value checked selected disabled),
            do: {key, LazyHTML.attribute(node, key)}

      {attrs, if(LazyHTML.attribute(node, "value") == [], do: words(node), else: "")}
    end)
    |> Enum.reject(fn {attrs, _} ->
      Enum.any?(attrs, fn {key, values} ->
        key == "name" and
          Enum.any?(values, &(&1 in ~w(authenticity_token _method import_id)))
      end)
    end)
  end

  defp reads(doc) do
    doc
    |> LazyHTML.query("a[href]")
    |> Enum.reject(fn node ->
      LazyHTML.attribute(node, "data-turbo-method") != []
    end)
    |> Enum.map(fn node -> {LazyHTML.attribute(node, "href"), words(node)} end)
  end
end
