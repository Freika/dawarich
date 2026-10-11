defmodule DawarichWeb.StandaloneShareAssetsTest do
  use Dawarich.IngestCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint DawarichWeb.Endpoint
  @moduletag :tmp_dir
  @id "a9f20000-0000-4000-8000-000000000001"
  defp host_conn, do: %{build_conn() | req_headers: [{"host", "www.example.com"}]}

  test "standalone phrase unlock loads the native module while retained legacy assets resolve",
       _ctx do
    id = user!()
    stamp = NaiveDateTime.utc_now()

    Repo.insert_all("shared_links", [
      %{
        id: Ecto.UUID.dump!(@id),
        user_id: id,
        resource_type: 2,
        name: "Synthetic timeline",
        magic_phrase: "synthetic-phrase",
        settings: %{"start_date" => "2026-05-09", "end_date" => "2026-05-12"},
        created_at: stamp,
        updated_at: stamp
      }
    ])

    gate = get(host_conn(), "/s/" <> @id)
    assert gate.status == 200
    assert String.contains?(gate.resp_body, "native-public-map") == false
    session = Dawarich.Test.RailsFormRequests.rails_session(gate)
    form = LazyHTML.from_document(gate.resp_body)

    [token] =
      form |> LazyHTML.query("input[name=authenticity_token]") |> LazyHTML.attribute("value")

    unlocked =
      Dawarich.Test.RailsFormRequests.post_form(
        session,
        URI.encode_query(%{"phrase" => "synthetic-phrase", "authenticity_token" => token}),
        [],
        "/s/" <> @id <> "/unlock"
      )

    assert unlocked.status == 302
    page = unlocked |> recycle() |> get("/s/" <> @id)
    assert page.status == 200
    assert String.contains?(page.resp_body, ~s(id="native-public-map")) == true
    assert String.contains?(page.resp_body, "data-controller") == false
    document = LazyHTML.from_document(page.resp_body)
    assert LazyHTML.query(document, "script[type=importmap]") |> Enum.count() == 0
    [native_src] = document |> LazyHTML.query("script[type=module]") |> LazyHTML.attribute("src")
    assert String.starts_with?(native_src, "/native/")
    native = get(host_conn(), native_src)
    assert native.status == 200
    assert get_resp_header(native, "content-type") == ["text/javascript"]
  end
end
