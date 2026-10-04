defmodule Dawarich.SharedApi.Photos do
  @moduledoc false

  def response(%{settings: %{"show_photos" => true}}, _action),
    do: {:replay, "shared photo search and ACL cache remain Rails"}

  def response(_link, :photos), do: {:ok, []}
  def response(_link, :thumbnail), do: {:head, 404}
end
