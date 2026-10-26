defmodule TextexpWeb.YDocRoomChannelTest do
  use Textexp.DataCase

  alias Textexp.Fixtures

  import Phoenix.ChannelTest

  alias Textexp.Document
  alias TextexpWeb.{UserSocket, YDocRoomChannel}

  @endpoint TextexpWeb.Endpoint

  defp register_user, do: Fixtures.register_user()

  defp join_as(user, document_id) do
    UserSocket
    |> socket("user_socket:#{user.id}", %{current_user: user})
    |> subscribe_and_join(YDocRoomChannel, "y_doc_room:#{document_id}")
  end

  # An edit of the text "t", as a Yjs client sends it.
  defp push_edit(socket, content) do
    source = Yex.Doc.new()
    source |> Yex.Doc.get_text("t") |> Yex.Text.insert(0, content)
    update = Yex.encode_state_as_update!(source)

    push(socket, "yjs", {:binary, Yex.Sync.message_encode!({:sync, {:sync_update, update}})})
    # the channel has handed the message to the DocServer
    _ = :sys.get_state(socket.channel_pid)
  end

  # Leaves the channel (which would start the DocServer again), then stops the
  # DocServer, which saves the document if it was edited, and gives the saved
  # text.
  defp saved_text(socket, document) do
    Process.unlink(socket.channel_pid)
    ref = Process.monitor(socket.channel_pid)
    close(socket)
    assert_receive {:DOWN, ^ref, :process, _pid, _reason}

    GenServer.stop(socket.assigns.doc_pid)

    case Document.get_document!(document.id).snapshot do
      nil ->
        nil

      snapshot ->
        doc = Yex.Doc.new()
        Yex.apply_update(doc, snapshot)
        doc |> Yex.Doc.get_text("t") |> Yex.Text.to_string()
    end
  end

  setup do
    owner = register_user()
    # Titled, so that it is kept, not deleted, when its DocServer stops.
    %{owner: owner, document: Fixtures.create_document!(owner, %{title: "Notes"})}
  end

  test "joining an unknown document is refused", %{owner: owner} do
    assert {:error, %{reason: "unauthorized"}} = join_as(owner, Ecto.UUID.generate())
  end

  test "joining another user's document is refused", %{document: document} do
    assert {:error, %{reason: "unauthorized"}} = join_as(register_user(), document.id)
  end

  test "the owner edits the document", %{owner: owner, document: document} do
    {:ok, _reply, socket} = join_as(owner, document.id)
    push_edit(socket, "hello")

    assert saved_text(socket, document) == "hello"
  end

  test "an editor edits the document", %{owner: owner, document: document} do
    editor = register_user()
    Fixtures.share!(owner, document, editor, :editor)

    {:ok, _reply, socket} = join_as(editor, document.id)
    push_edit(socket, "hello")

    assert saved_text(socket, document) == "hello"
  end

  # A Yjs client renews its unchanged awareness every 15 s, and the others
  # forget it if it is not renewed within 30 s.
  test "awareness renewals are relayed", %{owner: owner, document: document} do
    {:ok, _reply, socket} = join_as(owner, document.id)
    {:ok, client} = Yex.Awareness.new(Yex.Doc.new())

    for _renewal <- 1..2 do
      Yex.Awareness.set_local_state(client, %{"user" => "owner"})
      {:ok, update} = Yex.Awareness.encode_update(client, [Yex.Awareness.client_id(client)])
      push(socket, "yjs", {:binary, Yex.Sync.message_encode!({:awareness, update})})

      assert_broadcast "yjs", {:binary, <<1, _::binary>>}, 500
    end
  end

  test "a viewer joins, but its edits are dropped", %{owner: owner, document: document} do
    viewer = register_user()
    Fixtures.share!(owner, document, viewer, :viewer)

    {:ok, _reply, socket} = join_as(viewer, document.id)
    push_edit(socket, "hello")

    assert saved_text(socket, document) == nil
  end
end
