defmodule Dawarich.Posters.ScopedTest do
  use Dawarich.DataCase, async: true

  alias Dawarich.{Accounts, Maps, Posters}
  alias Dawarich.Posters.Persistence
  alias Dawarich.Test.RailsUser

  @recipe %{
    "name" => "Gallery",
    "title" => "Berlin",
    "theme" => "noir",
    "lat" => 52.52,
    "lon" => 13.405,
    "distance" => 6000,
    "start_at" => "2026-10-01T00:00",
    "end_at" => "2026-10-02T00:00",
    "source" => "tracks",
    "route_opacity" => "100",
    "route_width" => "100"
  }

  defp scope!(id) do
    RailsUser.insert!(%{id: id, email: "poster-#{id}@dawarich.test", api_key: "poster-key-#{id}"})
    Maps.principal(Accounts.get(id), "de")
  end

  defp effects do
    {rows("SELECT count(*) FROM phoenix.rails_commands") ++
       rows("SELECT count(*) FROM public.job_outbox"), rows("SELECT count(*) FROM posters")}
  end

  test "foreign poster command has no storage or outbox effect" do
    owner = scope!(96_301)
    other = scope!(96_302)
    {:ok, id} = Persistence.create(@recipe, %{id: owner.user.id}, "en")

    Repo.query!(
      "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES('poster-scoped-key','poster.png','image/png','{}','local',1,'x',now())"
    )

    [[blob]] = rows("SELECT id FROM active_storage_blobs WHERE key = 'poster-scoped-key'")

    Repo.query!(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('image','Poster',$1,$2,now())",
      [id, blob]
    )

    before = effects()

    assert {:error, :not_found} = Posters.delete(other, id)
    assert {:error, :not_found} = Posters.delete(other, Integer.to_string(id))
    assert {:error, :not_found} = Posters.card(other, id)
    assert {:ok, []} = Posters.gallery(other)
    assert effects() == before

    assert rows("SELECT count(*) FROM active_storage_attachments WHERE record_id = $1", [id]) == [
             [1]
           ]

    assert {:ok, ^id} = Posters.delete(owner, Integer.to_string(id))
    assert rows("SELECT count(*) FROM posters WHERE id = $1", [id]) == [[0]]
  end

  test "queued create stores only the scalar recipe and returns one location-free card" do
    scope = scope!(96_303)

    assert {:ok, card} =
             Posters.create(
               scope,
               Map.merge(@recipe, %{"user_id" => 1, "layout" => "x", "theme" => %{"a" => 1}})
             )

    assert %{name: "Gallery", status: 0, settings: settings, files: files} = card
    assert settings == %{}
    assert files == %{"image" => nil, "print_pdf" => nil}

    assert [[stored, user_id]] =
             rows("SELECT settings, user_id FROM posters WHERE id = $1", [card.id])

    assert user_id == scope.user.id
    assert stored == Map.drop(@recipe, ~w(name theme))
    assert {:ok, [listed]} = Posters.gallery(scope)
    assert listed.id == card.id
    refute inspect(listed) =~ "52.52"
    assert [[1]] = rows("SELECT count(*) FROM phoenix.rails_commands")
  end

  test "an empty poster recipe is refused like the Rails required poster params" do
    scope = scope!(96_305)
    before = effects()

    assert {:error, :invalid} = Posters.create(scope, %{})
    assert effects() == before
    assert {:ok, []} = Posters.gallery(scope)
  end

  test "revoked or invalid poster commands are refused without effects" do
    scope = scope!(96_304)
    {:ok, id} = Persistence.create(@recipe, %{id: scope.user.id}, "en")

    for value <- ["abc", "", nil, "99999999999999999999", %{}] do
      assert {:error, :not_found} = Posters.delete(scope, value)
    end

    assert {:error, :invalid} = Posters.create(scope, "not a map")

    Repo.query!("UPDATE users SET encrypted_password = $1 WHERE id = $2", [
      String.duplicate("changed", 10),
      scope.user.id
    ])

    before = effects()
    assert {:error, :stale_session} = Posters.create(scope, @recipe)
    assert {:error, :stale_session} = Posters.delete(scope, id)
    assert {:error, :stale_session} = Posters.card(scope, id)
    assert {:error, :stale_session} = Posters.gallery(scope)
    assert effects() == before
  end
end
