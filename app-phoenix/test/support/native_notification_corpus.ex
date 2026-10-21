defmodule Dawarich.Test.NativeNotificationCorpus do
  @moduledoc false
  import ExUnit.Assertions

  def assert_page(html, fixture) do
    native =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(
        "[data-testid=native-notifications-root], [data-testid=native-notifications-detail]"
      )

    expected = LazyHTML.from_fragment(fixture)
    assert Enum.count(native) == 1
    assert words(native) == words(expected)
    assert reads(native) == reads(expected)
    assert cards(native) == cards(expected)
  end

  defp words(doc),
    do: doc |> LazyHTML.to_tree() |> texts() |> Enum.join(" ") |> String.split() |> Enum.join(" ")

  defp texts(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &texts/1)
  defp texts({tag, _, _}) when tag in ["dialog", "script", "style"], do: []

  defp texts({"input", attrs, _}) do
    if {"type", "submit"} in attrs, do: [List.keyfind(attrs, "value", 0) |> elem(1)], else: []
  end

  defp texts({_, _, children}), do: texts(children)
  defp texts(text) when is_binary(text), do: [text]
  defp texts(_), do: []

  defp reads(doc) do
    doc
    |> LazyHTML.query("a[href]")
    |> Enum.reject(
      &(LazyHTML.attribute(&1, "data-turbo-method") != [] or
          LazyHTML.attribute(&1, "phx-click") != [])
    )
    |> Enum.map(&{LazyHTML.attribute(&1, "href"), words(&1)})
  end

  defp cards(doc) do
    doc
    |> LazyHTML.query("div[id^=notification_], div[id^=detail_notification_]")
    |> Enum.map(&{LazyHTML.attribute(&1, "id"), LazyHTML.attribute(&1, "role"), words(&1)})
  end
end
