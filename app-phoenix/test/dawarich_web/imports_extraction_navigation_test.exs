defmodule DawarichWeb.ImportsExtractionNavigationTest do
  use Dawarich.IngestCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Test.{RailsUser, ImportsExportsSeeds}
  @endpoint DawarichWeb.Endpoint

  test "extraction removal reconnects the document and polling delivers the reset button" do
    user = RailsUser.insert!(%{id: 7599, email: "extraction-navigation@example.test"})

    ImportsExportsSeeds.import!(%{
      id: 759_901,
      user_id: user.id,
      source: 0,
      additional_data_extraction_status: 3
    })

    conn = RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id)
    {:ok, view, _} = live(conn, "/imports/759901")

    assert has_element?(
             view,
             ~s(turbo-frame#import-759901-extraction[data-turbo="false"] form[action="/imports/759901/extraction"] button),
             "Remove extracted data"
           )

    Repo.query!("UPDATE imports SET additional_data_extraction_status=2 WHERE id=759901")
    {:ok, pending, _} = live(conn, "/imports/759901")
    assert :sys.get_state(pending.pid).socket.assigns.polling

    Repo.query!(
      "UPDATE imports SET additional_data_extraction_status=0,additional_data_extraction='{}' WHERE id=759901"
    )

    send(pending.pid, :imports_refresh)

    assert has_element?(
             pending,
             "button[data-action='click->import-extraction#open']",
             "Extract additional data"
           )

    refute :sys.get_state(pending.pid).socket.assigns.polling
  end
end
