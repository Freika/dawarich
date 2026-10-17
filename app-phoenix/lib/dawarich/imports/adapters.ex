defmodule Dawarich.Imports.Adapters do
  @moduledoc false
  alias Dawarich.Imports

  @adapters %{
    0 => Imports.GoogleSemanticHistory,
    1 => Imports.Owntracks,
    2 => Imports.GoogleRecords,
    3 => Imports.GooglePhone,
    4 => Imports.GpxImporter,
    5 => Imports.Photos,
    6 => Imports.Geojson,
    7 => Imports.Photos,
    9 => Imports.Kml,
    10 => Imports.Csv,
    11 => Imports.Tcx,
    12 => Imports.Fit,
    13 => Imports.Polarsteps,
    14 => Imports.GooglePhotos,
    15 => Imports.MobilePhotoLibrary
  }
  def fetch(source), do: Map.fetch(@adapters, source)
end
