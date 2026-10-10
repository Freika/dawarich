defmodule Dawarich.NativeM5.Dependencies do
  @moduledoc false
  def public_admit(grant, now, opts \\ []) do
    module = Keyword.get(opts, :admission, Dawarich.Sharing.Public)

    if Code.ensure_loaded?(module),
      do: apply(module, :admit, [grant, now]),
      else: {:error, :unavailable}
  end

  def public_photos(link), do: Dawarich.SharedApi.Photos.response(link, :photos)

  def public_description(body) do
    if Code.ensure_loaded?(Dawarich.Trips.Description),
      do: apply(Dawarich.Trips.Description, :render, [body]),
      else: Dawarich.Trips.RichContent.read(body)
  end
end
