poster = %{
  name: "Synthetic smoke",
  settings: %{
    "theme" => "terracotta",
    "lat" => "52.52",
    "lon" => "13.405",
    "distance" => "3000",
    "start_at" => "2025-10-15T12:00:00Z",
    "end_at" => "2025-10-15T12:02:00Z"
  }
}

track = %{
  "type" => "MultiLineString",
  "coordinates" => [[[13.405, 52.52], [13.406, 52.521], [13.407, 52.522]]]
}

%{png: png, pdf: pdf} = Dawarich.Posters.NativeRenderer.render(poster, track, "en")
<<137, 80, 78, 71, 13, 10, 26, 10, _::binary>> = png
<<"%PDF-", _::binary>> = pdf
true = byte_size(png) > 1000 and byte_size(pdf) > 1000
IO.puts("PASS native renderer synthetic PNG/PDF")
