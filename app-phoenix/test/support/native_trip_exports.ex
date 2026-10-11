defmodule Dawarich.Test.NativeTripExports do
  def prepare(html) do
    Regex.replace(
      ~r{<a data-turbo-method="post" href="(/trips/[1-9][0-9]*/export\?file_format=(?:gpx|json))">([^<]*)</a>},
      html,
      fn _, path, label ->
        ~s(<form method="post" action="#{path}" data-turbo="false"><input type="hidden" name="authenticity_token" value="CSRF"><button type="submit">#{label}</button></form>)
      end
    )
  end
end
