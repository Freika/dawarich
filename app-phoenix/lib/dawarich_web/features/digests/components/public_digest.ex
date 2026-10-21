defmodule DawarichWeb.PublicDigest do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.Digests
  alias DawarichWeb.{Chartkick, NativeDigestFlag, DigestFormat, Icon, YearCards}
  embed_templates "public_digest/*", suffix: "_template"

  def document(assigns) do
    digest = assigns.digest

    totals =
      assigns[:totals] ||
        %{
          countries: Digests.countries_count(digest.toponyms),
          cities: Digests.cities_count(digest.toponyms),
          first_countries: length(digest.first_time_countries),
          first_cities: length(digest.first_time_cities)
        }

    assigns
    |> assign(:totals, totals)
    |> assign(:native, assigns[:native] == true)
    |> document_template()
  end
end
