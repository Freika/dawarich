defmodule Dawarich.Cable.IdentityTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Cable.Identity
  alias Dawarich.Test.A12a

  setup do
    A12a.seed!()
    :ok
  end

  defp open, do: A12a.share!("live_open")
  defp always(_share), do: true
  defp never(_share), do: false

  test "share_id is cast like ActiveRecord's uuid type" do
    id = open().id
    assert Identity.cast(id) == id
    assert Identity.cast(String.upcase(id)) == id
    assert Identity.cast("{" <> id <> "}") == id
    assert Identity.cast(String.replace(id, "-", "")) == id
    assert Identity.cast("{" <> id) == nil
    assert Identity.cast("not-a-uuid") == nil
  end

  test "only an active live share counts, and a phrase needs the unlock cookie" do
    now = A12a.now()
    assert {:ok, %{id: _}} = Identity.share(open().id, &never/1, now)
    assert {:ok, nil} = Identity.share(A12a.share!("live_phrase").id, &never/1, now)
    assert {:ok, %{id: _}} = Identity.share(A12a.share!("live_phrase").id, &always/1, now)

    for name <- ~w(live_expired live_revoked timeline),
        do: assert({:ok, nil} = Identity.share(A12a.share!(name).id, &always/1, now))

    assert {:ok, nil} = Identity.share("   ", &always/1, now)
  end

  test "resolution follows ApplicationCable::Connection#connect, share first" do
    user = A12a.user!("alice")
    share = open()
    now = A12a.now()
    assert {:ok, %{user: ^user, share: nil}} = Identity.resolve(user, nil, &always/1, now)
    assert {:ok, %{user: nil, share: ^share}} = Identity.resolve(nil, share.id, &always/1, now)
    assert Identity.resolve(nil, nil, &always/1, now) == :unauthorized
    assert Identity.resolve({:locked, user}, share.id, &always/1, now) == :silent
    assert {:ok, %{user: ^user, share: ^share}} = Identity.resolve(user, share.id, &always/1, now)
  end

  test "share_id shapes follow the recorded Rails cases" do
    for name <- ~w(share_list share_hash share_open_braces share_open_blank share_invalid_uuid) do
      c = A12a.case!(name)
      resolved = Identity.resolve(nil, A12a.share_param(c), &always/1, A12a.now())
      assert A12a.expected_identity(c) == A12a.outcome(resolved), name
    end
  end
end
