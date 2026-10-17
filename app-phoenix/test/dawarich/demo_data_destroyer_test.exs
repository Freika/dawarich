defmodule Dawarich.DemoDataDestroyerTest do
  use Dawarich.DataCase, async: false
  alias Dawarich.{Accounts, DemoData.Destroyer, DemoData.Importer, Storage}
  alias Dawarich.Exports.PurgeWorker
  alias Dawarich.Test.{DemoData, RailsUser}

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")
    root = Path.join(System.tmp_dir!(), "demo-purge-" <> Ecto.UUID.generate())

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")

      File.rm_rf!(root)
    end)

    for id <- [976_801, 976_802] do
      RailsUser.insert!(%{id: id, email: "demo-destroy-#{id}@test"})
    end

    user = Accounts.get(976_801)
    assert Importer.call(Repo, user, DemoData.fixtures()) == :created

    ids =
      Map.new(~w(imports visits tracks trips places tags), fn table ->
        [[id]] = rows("SELECT id FROM #{table} WHERE user_id=$1", [user.id])
        {table, id}
      end)

    %{user: user, ids: ids, root: root}
  end

  test "demo destroy purges deleted record attachments storage first and retains shared blobs",
       c do
    blobs =
      for {table, type} <- [
            {"imports", "Import"},
            {"visits", "Visit"},
            {"tracks", "Track"},
            {"trips", "Trip"},
            {"tags", "Tag"}
          ] do
        {blob, path} = blob!(c.root)
        attach!(type, c.ids[table], blob)
        {blob, path}
      end

    {derived, derived_path} = blob!(c.root)
    attach!("Import", c.ids["imports"], derived, "prepared_file")
    [[point]] = rows("SELECT id FROM points WHERE user_id=$1 ORDER BY id LIMIT 1", [c.user.id])
    [[stat]] = rows("SELECT id FROM stats WHERE user_id=$1", [c.user.id])

    [[note]] =
      rows(
        "INSERT INTO notes(user_id,attachable_type,attachable_id,body,created_at,updated_at) VALUES($1,'Trip',$2,'Owned note',now(),now()) RETURNING id",
        [c.user.id, c.ids["trips"]]
      )

    [[rich_note]] =
      rows(
        "INSERT INTO action_text_rich_texts(name,record_type,record_id,body,created_at,updated_at) VALUES('body','Note',$1,'Synthetic rich note',now(),now()) RETURNING id",
        [note]
      )

    [[description]] =
      rows("SELECT id FROM action_text_rich_texts WHERE record_type='Trip' AND record_id=$1", [
        c.ids["trips"]
      ])

    extra =
      for {type, id} <- [
            {"Point", point},
            {"Stat", stat},
            {"Note", note},
            {"ActionText::RichText", rich_note},
            {"ActionText::RichText", description}
          ] do
        {blob, path} = blob!(c.root)
        attach!(type, id, blob, "extra")
        {blob, path}
      end

    {variant_blob, variant_path} = blob!(c.root)

    [[variant]] =
      rows(
        "INSERT INTO active_storage_variant_records(blob_id,variation_digest) VALUES($1,'Synthetic variation') RETURNING id",
        [derived]
      )

    attach!("ActiveStorage::VariantRecord", variant, variant_blob, "image")
    {shared, shared_path} = blob!(c.root)
    attach!("Import", c.ids["imports"], shared, "retained")

    [[foreign_import]] =
      rows(
        "INSERT INTO imports(user_id,name,created_at,updated_at) VALUES(976802,'Real import',now(),now()) RETURNING id"
      )

    attach!("Import", foreign_import, shared)
    before_shared = rows("SELECT * FROM active_storage_blobs WHERE id=$1", [shared])

    assert Destroyer.call(Repo, c.user) == :destroyed

    assert rows(
             "SELECT record_type,record_id FROM active_storage_attachments WHERE record_type IN ('Import','Visit','Track','Trip','Tag')"
           ) == [["Import", foreign_import]]

    targets = blobs ++ extra ++ [{derived, derived_path}, {variant_blob, variant_path}]
    ids = Enum.map(targets, &elem(&1, 0))

    assert rows("SELECT id FROM active_storage_blobs WHERE id=ANY($1) ORDER BY id", [ids]) ==
             Enum.map(Enum.sort(ids), &[&1])

    assert Enum.all?(targets, &File.exists?(elem(&1, 1)))
    assert rows("SELECT * FROM active_storage_blobs WHERE id=$1", [shared]) == before_shared
    jobs = rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'")
    assert jobs != []
    services = %{services: %{"local" => %{service: "local", root: c.root}}}
    {failed_blob, failed_path} = hd(blobs)
    File.rm!(failed_path)
    File.mkdir!(failed_path)
    [args] = Enum.find(jobs, fn [args] -> failed_blob in args["blob_ids"] end)
    assert {:error, {:storage_delete, _}} = PurgeWorker.run(args, repo: Repo, services: services)

    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [failed_blob]) == [
             [failed_blob]
           ]

    File.rmdir!(failed_path)
    File.write!(failed_path, "synthetic")
    for [args] <- jobs, do: assert(:ok == PurgeWorker.run(args, repo: Repo, services: services))
    assert rows("SELECT id FROM active_storage_blobs WHERE id=ANY($1)", [ids]) == []
    assert rows("SELECT id FROM active_storage_variant_records WHERE id=$1", [variant]) == []
    assert rows("SELECT record_type FROM active_storage_attachments") == [["Import"]]
    refute Enum.any?(targets, &File.exists?(elem(&1, 1)))
    assert File.exists?(shared_path)
    assert rows("SELECT * FROM active_storage_blobs WHERE id=$1", [shared]) == before_shared
  end

  test "demo destroy refuses foreign point associations without changing either owner", c do
    point = DemoData.real_point(976_802, 1_774_735_230)

    Repo.query!("UPDATE points SET visit_id=$2,track_id=$3 WHERE id=$1", [
      point,
      c.ids["visits"],
      c.ids["tracks"]
    ])

    before = snapshot()
    assert Destroyer.call(Repo, c.user) == :error
    assert snapshot() == before

    assert rows("SELECT user_id,visit_id,track_id FROM points WHERE id=$1", [point]) == [
             [976_802, c.ids["visits"], c.ids["tracks"]]
           ]
  end

  test "demo destroy leaves foreign extracted records linked to the removed marker", c do
    assert Importer.call(Repo, Accounts.get(976_802), DemoData.fixtures()) == :created

    for table <- ~w(visits places tracks) do
      Repo.query!("UPDATE #{table} SET demo=false,import_id=$1 WHERE user_id=976802", [
        c.ids["imports"]
      ])
    end

    before =
      Map.new(
        ~w(visits places tracks),
        &{&1, rows("SELECT to_jsonb(t) FROM #{&1} t WHERE user_id=976802")}
      )

    assert Destroyer.call(Repo, c.user) == :destroyed

    for {table, expected} <- before,
        do: assert(rows("SELECT to_jsonb(t) FROM #{table} t WHERE user_id=976802") == expected)

    assert rows("SELECT id FROM imports WHERE id=$1", [c.ids["imports"]]) == []
  end

  test "demo destroy refuses foreign notes shares visits and tags before dependent cleanup", c do
    for scenario <- [:note, :share, :visit, :tag, :tagged_place, :alternate] do
      assert {:error, :scenario} =
               Repo.transaction(fn ->
                 foreign_reference!(scenario, c.ids)
                 before = snapshot()
                 assert Destroyer.call(Repo, c.user) == :error
                 assert snapshot() == before
                 Repo.rollback(:scenario)
               end)
    end
  end

  defp foreign_reference!(:note, ids),
    do:
      rows(
        "INSERT INTO notes(user_id,attachable_type,attachable_id,body,created_at,updated_at) VALUES(976802,'Visit',$1,'Real note',now(),now())",
        [ids["visits"]]
      )

  defp foreign_reference!(:share, ids),
    do:
      rows(
        "INSERT INTO shared_links(user_id,resource_type,resource_id,name,created_at,updated_at) VALUES(976802,1,$1,'Real share',now(),now())",
        [ids["tracks"]]
      )

  defp foreign_reference!(:visit, ids),
    do:
      rows(
        "INSERT INTO visits(user_id,place_id,name,started_at,ended_at,duration,demo,created_at,updated_at) VALUES(976802,$1,'Foreign demo flag',now(),now(),0,true,now(),now())",
        [ids["places"]]
      )

  defp foreign_reference!(:tag, ids) do
    [[tag]] =
      rows(
        "INSERT INTO tags(user_id,name,created_at,updated_at) VALUES(976802,'Real tag',now(),now()) RETURNING id"
      )

    tagging!(tag, ids["places"])
  end

  defp foreign_reference!(scenario, ids) do
    [[place]] =
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,demo,created_at,updated_at) VALUES(976802,'Foreign demo flag',52,13,true,now(),now()) RETURNING id"
      )

    if scenario == :tagged_place,
      do: tagging!(ids["tags"], place),
      else:
        rows(
          "INSERT INTO place_visits(place_id,visit_id,created_at,updated_at) VALUES($1,$2,now(),now())",
          [place, ids["visits"]]
        )
  end

  defp tagging!(tag, place),
    do:
      rows(
        "INSERT INTO taggings(tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES($1,'Place',$2,now(),now())",
        [tag, place]
      )

  defp snapshot,
    do:
      Map.new(
        ~w(imports points visits places tracks trips tags notes taggings place_visits shared_links track_segments active_storage_attachments active_storage_blobs job_outbox),
        &{&1, rows("SELECT to_jsonb(t) FROM #{&1} t ORDER BY to_jsonb(t)::text")}
      )

  defp attach!(type, id, blob, name \\ "file"),
    do:
      rows(
        "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES($1,$2,$3,$4,now())",
        [name, type, id, blob]
      )

  defp blob!(root) do
    key = Storage.generate_key()

    [[id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,service_name,byte_size,created_at) VALUES($1,'synthetic','local',9,now()) RETURNING id",
        [key]
      )

    path = Storage.disk_path(root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "synthetic")
    {id, path}
  end
end
