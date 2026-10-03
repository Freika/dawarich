defmodule Dawarich.Test.ParityHTML do
  @moduledoc false
  import Kernel, except: [node: 1]

  @dropped_attribute ~r/^(phx-|data-phx-|data-testid$|data-status-display$|data-points-count$|data-controller$|data-action$|data-turbo|data-[a-z0-9-]+-(target|value|outlet|class|param)$)/
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
    case delete_action(tag, Map.new(attrs), children) do
      {:ok, action} -> [action]
      :unchanged -> ordinary_node(tag, attrs, children)
    end
  end

  defp delete_action("a", %{"href" => path, "data-turbo-method" => "delete"} = attrs, children) do
    if Regex.match?(~r|^/imports/[1-9][0-9]*$|, path) do
      {:ok,
       action(
         path,
         Map.get(attrs, "data-turbo-confirm"),
         Map.drop(attrs, ["href", "data-turbo-method", "data-turbo-confirm"]),
         children
       )}
    else
      :unchanged
    end
  end

  defp delete_action("form", %{"action" => path, "method" => "post"} = attrs, children) do
    nodes = Enum.reject(children, fn child -> is_binary(child) and String.trim(child) == "" end)
    inputs = for {"input", input_attrs, []} <- nodes, do: Map.new(input_attrs)
    buttons = for {"button", button_attrs, visible} <- nodes, do: {Map.new(button_attrs), visible}
    input_values = Map.new(inputs, &{&1["name"], &1["value"]})

    case buttons do
      [{button, visible}] ->
        valid =
          Regex.match?(~r|^/imports/[1-9][0-9]*$|, path) and
            length(nodes) == 4 and length(inputs) == 3 and
            Enum.all?(
              inputs,
              &(&1["type"] == "hidden" and Enum.sort(Map.keys(&1)) == ~w(name type value))
            ) and
            Enum.sort(Map.keys(input_values)) == ~w(_method authenticity_token import_id) and
            input_values["_method"] == "delete" and
            input_values["import_id"] == List.last(String.split(path, "/")) and
            is_binary(input_values["authenticity_token"]) and
            input_values["authenticity_token"] != "" and
            Map.get(button, "type", "submit") == "submit"

        if valid do
          extra_form =
            attrs
            |> Map.drop(["action", "method"])
            |> Enum.reject(fn {key, _} -> Regex.match?(@dropped_attribute, key) end)

          control =
            button
            |> Map.drop(["type", "data-confirm"])
            |> Map.merge(Map.new(extra_form, fn {key, value} -> {"form-" <> key, value} end))

          {:ok, action(path, button["data-confirm"], control, visible)}
        else
          :unchanged
        end

      _ ->
        :unchanged
    end
  end

  defp delete_action(_, _, _), do: :unchanged

  defp action(path, confirmation, attrs, children) do
    control =
      attrs
      |> Enum.reject(fn {key, _} -> Regex.match?(@dropped_attribute, key) end)
      |> Enum.map(fn {key, val} -> {key, value("button", key, val, attrs)} end)

    {"delete-action",
     Enum.sort([{"path", path}, {"method", "delete"}, {"confirmation", confirmation} | control]),
     normalize(children)}
  end

  defp ordinary_node(tag, attrs, children) do
    attrs = Map.new(attrs)

    if Map.has_key?(attrs, "data-phx-main") do
      normalize(children)
    else
      kept =
        attrs
        |> Enum.reject(fn {name, value} -> dropped?(name, value) end)
        |> Enum.map(fn {name, value} -> {name, value(tag, name, value, attrs)} end)
        |> Enum.sort()

      [{tag, kept, normalize(children)}]
    end
  end

  defp dropped?("id", "phx-" <> _), do: true
  defp dropped?(name, _value), do: Regex.match?(@dropped_attribute, name)

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

  def first_difference(left, right, path \\ "root")
  def first_difference(same, same, _path), do: "equal"

  def first_difference(left, right, path) when is_list(left) and is_list(right) do
    case Enum.zip(left, right) |> Enum.find_index(fn {a, b} -> a != b end) do
      nil ->
        extra = Enum.drop(left, length(right)) ++ Enum.drop(right, length(left))

        "#{path}: child counts #{length(left)} != #{length(right)}, extra #{inspect(extra, limit: 8)}"

      index ->
        first_difference(Enum.at(left, index), Enum.at(right, index), "#{path}[#{index}]")
    end
  end

  def first_difference({tag, attrs, children}, {tag, attrs, expected}, path),
    do: first_difference(children, expected, path <> "/" <> tag)

  def first_difference({tag, attrs, _}, {tag, expected, _}, path),
    do: "#{path}/#{tag}: attributes #{inspect(attrs)} != #{inspect(expected)}"

  def first_difference(left, right, path),
    do: "#{path}: #{inspect(left, limit: 8)} != #{inspect(right, limit: 8)}"
end
