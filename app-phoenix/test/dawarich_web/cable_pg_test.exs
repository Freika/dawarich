defmodule DawarichWeb.CablePgTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Cable.{Bus, Frames, PgStore}
  alias Dawarich.ScratchRepo
  alias Dawarich.Test.A12a

  setup do
    Dawarich.JobsCase.reset!(ScratchRepo)
    A12a.seed!()
    cable = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg, repo: ScratchRepo, polling: false)
    on_exit(fn -> Application.put_env(:dawarich, :cable, cable) end)
    [spec] = Bus.child_specs()
    start_supervised!(spec)
    {:ok, port: A12a.serve_cable!()}
  end

  test "alias subscription preserves an active broadcasting fence and delivery after alias removal",
       %{port: port} do
    recorded = A12a.case!("points_alias")["steps"]

    ids =
      for %{"send" => text} <- recorded,
          %{"command" => "subscribe", "identifier" => id} <- [Jason.decode!(text)],
          do: id

    [first, other] = ids

    confirmations =
      for %{"expect" => frame} <- recorded, frame =~ "confirm_subscription", do: frame

    messages =
      for %{"expect" => frame} <- recorded,
          Map.has_key?(Jason.decode!(frame), "message"),
          do: frame

    payloads = for %{"publish" => publication} <- recorded, do: publication["payload"]
    [both, remaining] = payloads
    broadcasting = A12a.broadcasting("points", "alice")
    namespace = Bus.prefix() || ""
    socket = A12a.open!(port, A12a.cookie("alice"))
    on_exit(fn -> :gen_tcp.close(socket) end)
    assert A12a.next_frame(socket) == %{"expect" => Frames.welcome()}

    subscribe(socket, first)
    assert A12a.next_frame(socket) == %{"expect" => Enum.at(confirmations, 0)}
    assert {:ok, 1} = PgStore.append(ScratchRepo, namespace, broadcasting, both)
    subscribe(socket, other)
    assert A12a.next_frame(socket) == %{"expect" => Enum.at(confirmations, 1)}
    poll()
    delivered = for _ <- 1..2, do: A12a.next_frame(socket)["expect"]
    assert Enum.sort(delivered) == Enum.sort(Enum.take(messages, 2))

    A12a.send_text(socket, Jason.encode!(%{command: "unsubscribe", identifier: other}))
    barrier = ~s({"channel":"FamilyLocationsChannel"})
    subscribe(socket, barrier)
    assert A12a.next_frame(socket) == %{"expect" => Frames.reject(barrier)}
    assert {:ok, 2} = PgStore.append(ScratchRepo, namespace, broadcasting, remaining)
    poll()
    assert A12a.next_frame(socket) == %{"expect" => Enum.at(messages, 2)}

    A12a.send_text(socket, Jason.encode!(%{command: "unsubscribe", identifier: first}))

    assert {:ok, 3} =
             PgStore.append(ScratchRepo, namespace, broadcasting, "\"before fresh fence\"")

    subscribe(socket, first)
    assert A12a.next_frame(socket) == %{"expect" => Frames.confirm(first)}
    assert {:ok, 4} = PgStore.append(ScratchRepo, namespace, broadcasting, "\"fresh\"")
    poll()
    assert A12a.next_frame(socket) == %{"expect" => Frames.message(first, "\"fresh\"")}
    assert A12a.next_frame(socket, 100) == %{"error" => ":timeout"}
  end

  defp subscribe(socket, id),
    do: A12a.send_text(socket, Jason.encode!(%{command: "subscribe", identifier: id}))

  defp poll do
    send(Bus, :poll)
    :sys.get_state(Bus)
  end
end
