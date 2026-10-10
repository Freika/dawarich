defmodule Dawarich.Test.NativeAuthHTTP do
  @moduledoc false

  def fields(html) do
    for node <- LazyHTML.query(LazyHTML.from_fragment(html), "input") do
      for key <- ~w(name type value id) do
        value =
          if key == "value" and LazyHTML.attribute(node, "name") == ["authenticity_token"],
            do: ["CSRF"],
            else: LazyHTML.attribute(node, key)

        {key, value}
      end
    end
  end

  def text(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.map(fn node ->
      LazyHTML.text(node) |> String.replace(~r/\s+/, " ") |> String.trim()
    end)
    |> Enum.join(" ")
  end
end
