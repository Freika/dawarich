defmodule DawarichWeb.TripRichTextTest do
  use Dawarich.DataCase, async: true

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Dawarich.Accounts
  alias Dawarich.Accounts.Scope
  alias Dawarich.Storage.UploadReceipts
  alias Dawarich.Test.TripsSeeds
  alias DawarichWeb.TripsNative.{Access, RichUpload}

  @checksum "AELTPXGTbs81Ygn6v0o2PQ=="

  defp socket(id) do
    TripsSeeds.user!(id)
    scope = Scope.for_user(Accounts.get(id), "en")

    Access.put_principal(
      %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, base_url: "http://www.example.com"}},
      Access.principal(scope)
    )
  end

  defp reserve(socket, name \\ "photo.png") do
    {:reply, reply, socket} =
      RichUpload.handle(
        "rich_upload_reserve",
        %{"name" => name, "size" => 9, "type" => "image/png", "checksum" => @checksum},
        socket
      )

    {reply, socket}
  end

  defp blob_id(name),
    do: hd(hd(rows("SELECT id FROM active_storage_blobs WHERE filename=$1", [name])))

  test "the editor keeps the rich body inside an ignored hook container with a label" do
    html =
      rendered_to_string(
        DawarichWeb.TripRichText.editor(%{
          __changed__: nil,
          id: "trip-description",
          name: "trip[rich_description_sgid]",
          value: "<div>Saved</div>",
          revision: 3,
          label: "Notes",
          locale: "en"
        })
      )

    doc = LazyHTML.from_fragment(html)
    root = LazyHTML.query(doc, "#trip-description[phx-hook='RichText'][phx-update='ignore']")
    assert LazyHTML.attribute(root, "data-revision") == ["3"]

    assert LazyHTML.query(doc, "input[type='hidden'][name='trip[rich_description_sgid]']")
           |> LazyHTML.attribute("value") == ["<div>Saved</div>"]

    assert LazyHTML.query(doc, "trix-editor[input='trip-description-input'][aria-label='Notes']")
           |> Enum.count() == 1

    assert LazyHTML.query(doc, "[data-rich-status][role='status']") |> Enum.count() == 1
  end

  test "a reserved upload claims only the actor's own fresh blob, once" do
    owner = socket(9_801)
    {reply, owner} = reserve(owner)
    assert %{upload_ref: ref, url: url} = reply
    assert url =~ "/rails/active_storage/disk/"
    id = blob_id("photo.png")
    assert UploadReceipts.owned?(Repo, id, 9_801)

    assert {:reply, claimed, owner} =
             RichUpload.handle("rich_upload_claim", %{"upload_ref" => ref}, owner)

    assert claimed.sgid == Dawarich.RailsMessages.attachable_sgid(id)
    assert claimed.url =~ "/rails/active_storage/blobs/redirect/"
    assert claimed.href == claimed.url <> "?disposition=attachment"

    assert {:reply, %{error: "refused"}, _} =
             RichUpload.handle("rich_upload_claim", %{"upload_ref" => ref}, owner)

    stranger = socket(9_802)
    forged = %{stranger | private: Map.put(stranger.private, :rich_uploads, %{"forged" => id})}

    assert {:reply, %{error: "refused"}, _} =
             RichUpload.handle("rich_upload_claim", %{"upload_ref" => "forged"}, forged)

    assert {:reply, %{error: "refused"}, _} =
             RichUpload.handle(
               "rich_upload_reserve",
               %{"name" => "x", "size" => -1, "checksum" => @checksum},
               owner
             )
  end

  test "a cancelled upload queues purge of its reserved blob" do
    owner = socket(9_803)
    {%{upload_ref: ref}, owner} = reserve(owner, "cancelled.png")

    assert {:noreply, owner} =
             RichUpload.handle("rich_upload_cancel", %{"upload_ref" => ref}, owner)

    assert owner.private.rich_uploads == %{}

    assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'") ==
             [[1]]
  end

  test "a stale actor cannot reserve or claim" do
    owner = socket(9_804)

    Repo.query!("UPDATE users SET encrypted_password=$2 WHERE id=$1", [
      9_804,
      String.duplicate("x", 60)
    ])

    assert {%{error: "refused"}, _} = reserve(owner)
    assert rows("SELECT count(*) FROM active_storage_blobs") == [[0]]
  end

  defmodule Crasher do
    use GenServer
    def init(state), do: {:ok, state}

    def handle_info(%Phoenix.Socket.Message{payload: %{"value" => value}}, _state),
      do: clause(value)

    defp clause(%{"never" => true}), do: :ok
  end

  test "a capability-bearing failed editor event is redacted in the crash log" do
    sgid = "synthetic-sgid-b4-capability"

    body =
      URI.encode_www_form(
        ~s(<div><action-text-attachment sgid="#{sgid}"></action-text-attachment></div>)
      )

    log =
      capture_log(fn ->
        {:ok, pid} = GenServer.start(Crasher, %{})
        ref = Process.monitor(pid)

        send(pid, %Phoenix.Socket.Message{
          topic: "lv:phx-trip-form",
          event: "event",
          payload: %{
            "event" => "save",
            "type" => "form",
            "value" => %{
              "form" => "trip%5Bname%5D=Coast&trip%5Brich_description_sgid%5D=" <> body,
              "upload_ref" => "synthetic-upload-ref-b4"
            }
          }
        })

        assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
        Logger.flush()
      end)

    assert log =~ "FunctionClauseError"
    refute log =~ sgid
    refute log =~ "synthetic-upload-ref-b4"
  end
end
