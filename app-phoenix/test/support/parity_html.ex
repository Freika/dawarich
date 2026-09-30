defmodule Dawarich.Test.ParityHTML do
  @moduledoc false
  import Kernel, except: [node: 1]

  @dropped_attribute ~r/^(phx-|data-phx-|data-controller$|data-action$|data-turbo|data-[a-z0-9-]+-(target|value|outlet|class|param)$)/
  @dropped_elements ~w(turbo-cable-stream-source)

  def normalize(html) when is_binary(html),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> normalize()

  def normalize(nodes) when is_list(nodes) do
    nodes |> Enum.flat_map(&node/1) |> Enum.reject(&(&1 == ""))
  end

  def fragment(html, selector),
    do:
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(selector)
      |> LazyHTML.to_tree()
      |> normalize()

  def without(html, selectors, root_selector \\ "body") do
    doc = LazyHTML.from_document(html)
    tree = doc |> LazyHTML.query(root_selector) |> LazyHTML.to_tree()
    drop = selectors |> Enum.flat_map(&(doc |> LazyHTML.query(&1) |> LazyHTML.to_tree()))
    tree |> prune(drop) |> normalize()
  end

  @stimulus "[data-controller], [data-action], [data-stat-page-target], [data-sharing-modal-target]"

  def stimulus(html, selector \\ @stimulus) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.to_tree()
    |> Enum.map(fn {tag, attrs, _children} ->
      {tag,
       attrs |> Enum.filter(fn {name, _} -> String.starts_with?(name, "data-") end) |> Enum.sort()}
    end)
  end

  defp node({:comment, _}), do: []

  defp node(text) when is_binary(text),
    do: [text |> String.replace(~r/\s+/, " ") |> String.trim()]

  defp node({tag, _attrs, _children}) when tag in @dropped_elements, do: []

  defp node({tag, attrs, children}) do
    attrs = Map.new(attrs)

    if Map.has_key?(attrs, "data-phx-main") do
      normalize(children)
    else
      kept =
        attrs
        |> Enum.reject(fn {name, _} -> Regex.match?(@dropped_attribute, name) end)
        |> Enum.map(fn {name, value} -> {name, value(tag, name, value, attrs)} end)
        |> Enum.sort()

      [{tag, kept, normalize(children)}]
    end
  end

  defp value("meta", "content", _value, %{"name" => name})
       when name in ["csrf-token", "phoenix-csrf-token"],
       do: "CSRF"

  defp value("meta", "content", value, %{"name" => "msapplication-config"}), do: undigest(value)

  defp value("input", "value", _value, %{"name" => "authenticity_token"}), do: "CSRF"

  defp value(_tag, "style", value, _attrs),
    do: Regex.replace(~r/url\('([^']*)'\)/, value, fn _, url -> "url('#{undigest(url)}')" end)

  defp value(_tag, "class", value, _attrs), do: value |> String.split() |> Enum.join(" ")
  defp value(_tag, name, value, _attrs) when name in ["href", "src"], do: undigest(value)
  defp value(_tag, _name, value, _attrs), do: value

  defp undigest(url) do
    path = URI.parse(url).path

    url
    |> undigest_asset(path)
    |> undigest_query(path)
  end

  defp undigest_asset(url, "/assets/" <> _rest),
    do: String.replace(url, ~r/-[0-9a-f]{8,}(?=\.\w+(?:[?"]|$))/, "")

  defp undigest_asset(url, _path), do: url

  defp undigest_query(url, "/auth/dawarich"),
    do: String.replace(url, ~r/([?&]token=)[^&"]+/, "\\1X")

  defp undigest_query(url, "/assets/" <> _rest),
    do: String.replace(url, ~r/([?&]vsn=)[^&"]+/, "\\1X")

  defp undigest_query(url, "/phoenix/js/" <> _rest),
    do: String.replace(url, ~r/([?&]vsn=)[^&"]+/, "\\1X")

  defp undigest_query(url, _path), do: url

  defp prune(nodes, drop) when is_list(nodes),
    do: for(node <- nodes, node not in drop, do: prune(node, drop))

  defp prune({tag, attrs, children}, drop), do: {tag, attrs, prune(children, drop)}
  defp prune(other, _drop), do: other
end
