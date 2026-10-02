defmodule Dawarich.Test.MapStimulus do
  @moduledoc false

  @stimulus ~r/^(data-controller|data-action|data-turbo.*|data-[a-z0-9-]+-(target|value|outlet|class|param))$/
  @regions ["#map-shell", "#share-link-modal", "#demo-data-banner", "#map-footer"]
  @roots ["map-shell", "share-link-modal", "demo-data-banner"]
  @islands Enum.join(
             [
               "[data-controller~='onboarding-modal']",
               "[data-controller~='onboarding-modal'] [data-controller]",
               "[data-controller~='onboarding-modal'] [data-action]",
               "[data-controller~='onboarding-modal'] [data-onboarding-modal-target]",
               "[data-controller~='onboarding-modal'] [data-upload-target]",
               "#achievement-unlocks"
             ],
             ", "
           )

  def prepare(html) do
    html
    |> String.replace(~r{(/rails/active_storage/blobs/redirect/)[^/"]+}, "\\1SIGNED")
    |> String.replace(~r{(/auth/dawarich\?token=)[^&"]+}, "\\1X")
    |> String.replace(~r|(/assets/[^"'\s]*?)-[0-9a-f]{8,}(\.\w+)|, "\\1\\2")
  end

  def attributes(html) do
    doc = LazyHTML.from_document(html)

    regions =
      for region <- @regions,
          {tag, attrs, _children} <-
            doc |> LazyHTML.query("#{region}, #{region} *") |> LazyHTML.to_tree(),
          kept = kept(attrs),
          kept != [],
          do: {region, tag, kept}

    regions ++ Dawarich.Test.ParityHTML.stimulus(html, @islands)
  end

  defp kept(attrs) do
    root? = match?({"id", id} when id in @roots, List.keyfind(attrs, "id", 0))

    attrs
    |> Enum.filter(fn {name, _value} ->
      Regex.match?(@stimulus, name) and not (root? and name == "data-turbo")
    end)
    |> Enum.sort()
  end
end
