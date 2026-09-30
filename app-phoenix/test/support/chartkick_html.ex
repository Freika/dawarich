defmodule Dawarich.Test.ChartkickHTML do
  @moduledoc false

  @script ~r/<script>\s*\(function\(\) \{.*?<\/script>/s
  @create ~r/new Chartkick\[("\w+")\]\(("[^"]*"), (\[.*?\]), (\{.*\})\); \};/

  def without_charts(html), do: Regex.replace(@script, html, "")

  def charts(html) do
    for [_, type, id, data, options] <- Regex.scan(@create, html) do
      %{
        type: Jason.decode!(type),
        id: Jason.decode!(id),
        data: Jason.decode!(data),
        options: Jason.decode!(options)
      }
    end
  end
end
