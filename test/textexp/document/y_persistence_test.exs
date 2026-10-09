defmodule Textexp.Document.YPersistenceTest do
  use Textexp.DataCase

  alias Textexp.Document
  alias Textexp.Document.YPersistence
  alias TextexpWeb.DocServer

  defp register_user do
    Textexp.Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: "persistence-#{System.unique_integer([:positive])}@example.com",
      password: "a-long-password",
      password_confirmation: "a-long-password"
    })
    |> Ash.create!(authorize?: false)
  end

  defp text_update(content) do
    source = Yex.Doc.new()
    source |> Yex.Doc.get_text("t") |> Yex.Text.insert(0, content)
    Yex.encode_state_as_update!(source)
  end

  defp loaded_text(document_id) do
    doc = Yex.Doc.new()
    YPersistence.bind(%{}, document_id, doc)
    doc |> Yex.Doc.get_text("t") |> Yex.Text.to_string()
  end

  setup do
    %{document: Document.create_document!(%{}, actor: register_user())}
  end

  test "loading a document compacts its leftover writings", %{document: document} do
    YPersistence.update_v1(%{}, text_update("hello"), document.id, nil)

    assert loaded_text(document.id) == "hello"
    assert Document.list_writings!(document.id) == []
    assert Document.get_document!(document.id).snapshot
  end

  test "unbind compacts the writings into the snapshot", %{document: document} do
    YPersistence.update_v1(%{}, text_update("hello"), document.id, nil)

    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    YPersistence.unbind(state, document.id, doc)

    assert Document.list_writings!(document.id) == []
    assert Document.get_document!(document.id).snapshot
    assert loaded_text(document.id) == "hello"
  end

  defp start_doc_server(document) do
    start_supervised!(%{
      id: DocServer,
      start:
        {DocServer, :start_link,
         [[topic: "y_doc_room:#{document.id}", doc_name: document.id], []]}
    })
  end

  # Envoie une modification au DocServer comme le ferait un client.
  defp edit(pid, content) do
    {:ok, sync} = Yex.Sync.get_update(text_update(content))
    {:ok, message} = Yex.Sync.message_encode({:sync, sync})
    DocServer.process_message_v1(pid, message, self())
    # applique le message, puis traite la notification d'update qui en découle
    _ = :sys.get_state(pid)
    _ = :sys.get_state(pid)
  end

  test "starting a DocServer does not re-persist the loaded content", %{document: document} do
    YPersistence.update_v1(%{}, text_update("hello"), document.id, nil)

    pid = start_doc_server(document)
    # the load-time update message is handled before this call returns
    _ = :sys.get_state(pid)

    assert Document.list_writings!(document.id) == []
  end

  describe "flush" do
    test "happens after 400 writings", %{document: document} do
      doc = Yex.Doc.new()
      state = YPersistence.bind(%{}, document.id, doc)

      state =
        Enum.reduce(1..399, state, fn i, state ->
          YPersistence.update_v1(state, text_update("#{i}"), document.id, doc)
        end)

      assert length(Document.list_writings!(document.id)) == 399

      YPersistence.update_v1(state, text_update("400"), document.id, doc)

      assert Document.list_writings!(document.id) == []
      assert Document.get_document!(document.id).snapshot
    end

    test "happens periodically in the DocServer", %{document: document} do
      pid = start_doc_server(document)
      edit(pid, "hello")
      assert length(Document.list_writings!(document.id)) == 1

      # message normalement envoyé par le timer du DocServer
      send(pid, :flush)
      _ = :sys.get_state(pid)

      assert Document.list_writings!(document.id) == []
      assert loaded_text(document.id) == "hello"
    end

    test "happens when the DocServer is shut down by its supervisor", %{document: document} do
      pid = start_doc_server(document)
      edit(pid, "hello")
      assert length(Document.list_writings!(document.id)) == 1

      stop_supervised!(DocServer)

      assert Document.list_writings!(document.id) == []
      assert loaded_text(document.id) == "hello"
    end

    test "does nothing without pending writings", %{document: document} do
      doc = Yex.Doc.new()
      state = YPersistence.bind(%{}, document.id, doc)

      assert YPersistence.flush(state, document.id, doc) == state
      refute Document.get_document!(document.id).snapshot
    end
  end

  describe "last_update" do
    test "is the latest writing, or updated_at once compacted", %{document: document} do
      assert Document.get_document!(document.id, load: [:last_update]).last_update ==
               document.updated_at

      writing = Document.add_writing!(document.id, text_update("hello"))

      assert Document.get_document!(document.id, load: [:last_update]).last_update ==
               writing.inserted_at

      doc = Yex.Doc.new()
      state = YPersistence.bind(%{}, document.id, doc)
      YPersistence.unbind(state, document.id, doc)

      compacted = Document.get_document!(document.id, load: [:last_update])
      assert compacted.last_update == compacted.updated_at
      assert DateTime.compare(compacted.last_update, writing.inserted_at) != :lt
    end
  end

  test "broadcasts content updates on the document topic, throttled", %{document: document} do
    Phoenix.PubSub.subscribe(Textexp.PubSub, YPersistence.topic(document.id))
    document_id = document.id

    state = YPersistence.update_v1(%{}, text_update("a"), document_id, nil)
    assert_receive {:document_updated, ^document_id, %DateTime{}}

    YPersistence.update_v1(state, text_update("b"), document_id, nil)
    refute_receive {:document_updated, _, _}
  end
end
