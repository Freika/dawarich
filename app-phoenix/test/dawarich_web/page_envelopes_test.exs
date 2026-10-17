defmodule DawarichWeb.PageEnvelopesTest do
  use ExUnit.Case, async: true

  @review Map.new(~w(f3 f5 f8), fn name ->
            {name,
             Jason.decode!(
               File.read!(Path.expand("../fixtures/page_envelopes/#{name}.json", __DIR__))
             )}
          end)

  test "F3 source negotiation qualities parameters and stable ties survive calendar retirement" do
    for probe <- @review["f3"]["negotiation"] do
      assert DawarichWeb.PageAccept.formats(probe["accept"], probe["xhr"]) == probe["formats"]
    end
  end

  test "F5 leading decimal source negotiation survives calendar retirement in both directions" do
    for {accept, source} <- @review["f5"], do: assert_negotiation(accept, true, source)
  end

  test "F8 dotted exponent numeric prefixes preserve source negotiation after calendar retirement in both XHR modes" do
    for %{"accept" => accept, "xhr" => xhr, "response" => source} <- @review["f8"],
        do: assert_negotiation(accept, xhr, source)
  end

  defp assert_negotiation(accept, xhr, source) do
    formats = DawarichWeb.PageAccept.formats(accept, xhr)

    assert DawarichWeb.PageAccept.negotiate(formats, ["text/html", "text/vnd.turbo-stream.html"]) ==
             source["type"]
  end
end
