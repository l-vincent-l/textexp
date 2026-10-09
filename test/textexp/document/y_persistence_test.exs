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

  defp text(doc), do: doc |> Yex.Doc.get_text("t") |> Yex.Text.to_string()

  defp loaded_text(document_id) do
    doc = Yex.Doc.new()
    YPersistence.bind(%{}, document_id, doc)
    text(doc)
  end

  # Applique une modification à `doc` et la signale à la persistance, comme le
  # fait le DocServer.
  defp edit(state, document, doc, content) do
    update = text_update(content)
    Yex.apply_update(doc, update)
    YPersistence.update_v1(state, update, document.id, doc)
  end

  setup do
    %{document: Document.create_document!(%{}, actor: register_user())}
  end

  test "loading applies the saved snapshot", %{document: document} do
    Document.save_snapshot!(document, text_update("hello"))

    assert loaded_text(document.id) == "hello"
  end

  test "edits are not written until the document is flushed", %{document: document} do
    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    state = edit(state, document, doc, "hello")

    refute Document.get_document!(document.id).snapshot

    YPersistence.flush(state, document.id, doc)

    assert loaded_text(document.id) == "hello"
  end

  test "flush does nothing when nothing changed", %{document: document} do
    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)

    assert YPersistence.flush(state, document.id, doc) == state
    assert Document.get_document!(document.id).updated_at == document.updated_at
  end

  test "flush only writes once per batch of edits", %{document: document} do
    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    state = edit(state, document, doc, "hello")

    state = YPersistence.flush(state, document.id, doc)
    saved = Document.get_document!(document.id)

    assert YPersistence.flush(state, document.id, doc) == state
    assert Document.get_document!(document.id).updated_at == saved.updated_at
  end

  test "unbind saves pending edits", %{document: document} do
    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    state = edit(state, document, doc, "hello")

    YPersistence.unbind(state, document.id, doc)

    assert loaded_text(document.id) == "hello"
  end

  test "flush broadcasts the save time on the document topic", %{document: document} do
    Phoenix.PubSub.subscribe(Textexp.PubSub, YPersistence.topic(document.id))
    document_id = document.id

    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    state = edit(state, document, doc, "hello")
    YPersistence.flush(state, document.id, doc)

    updated_at = Document.get_document!(document.id).updated_at
    assert_receive {:document_updated, ^document_id, ^updated_at}
  end

  test "last_update is the time of the last save", %{document: document} do
    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    state = edit(state, document, doc, "hello")
    YPersistence.flush(state, document.id, doc)

    saved = Document.get_document!(document.id, load: [:last_update])
    assert saved.last_update == saved.updated_at
    assert DateTime.compare(saved.last_update, document.updated_at) == :gt
  end

  test "emits a telemetry event for each database operation", %{document: document} do
    test_pid = self()
    handler_id = "y-persistence-test-#{inspect(test_pid)}"

    :telemetry.attach(
      handler_id,
      [:textexp, :y_persistence, :stop],
      fn _event, measurements, metadata, _config ->
        send(test_pid, {:y_persistence, metadata.operation, measurements.duration})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    assert_receive {:y_persistence, :load, duration} when is_integer(duration)

    state = edit(state, document, doc, "hello")
    refute_received {:y_persistence, _, _}

    YPersistence.flush(state, document.id, doc)
    assert_receive {:y_persistence, :save, _}
  end

  describe "DocServer" do
    defp start_doc_server(document) do
      start_supervised!(%{
        id: DocServer,
        start:
          {DocServer, :start_link,
           [[topic: "y_doc_room:#{document.id}", doc_name: document.id], []]}
      })
    end

    # Envoie une modification au DocServer comme le ferait un client.
    defp send_edit(pid, content) do
      {:ok, sync} = Yex.Sync.get_update(text_update(content))
      {:ok, message} = Yex.Sync.message_encode({:sync, sync})
      DocServer.process_message_v1(pid, message, self())
      # applique le message, puis traite la notification d'update qui en découle
      _ = :sys.get_state(pid)
      _ = :sys.get_state(pid)
    end

    test "starting does not write anything", %{document: document} do
      Document.save_snapshot!(document, text_update("hello"))
      saved = Document.get_document!(document.id)

      pid = start_doc_server(document)
      # the load-time update message is handled before this call returns
      _ = :sys.get_state(pid)
      send(pid, :flush)
      _ = :sys.get_state(pid)

      assert Document.get_document!(document.id).updated_at == saved.updated_at
    end

    test "edits are saved by the periodic flush", %{document: document} do
      pid = start_doc_server(document)
      send_edit(pid, "hello")

      refute Document.get_document!(document.id).snapshot

      # message normalement envoyé par le timer du DocServer
      send(pid, :flush)
      _ = :sys.get_state(pid)

      assert loaded_text(document.id) == "hello"
    end

    test "edits are saved when the DocServer is shut down", %{document: document} do
      pid = start_doc_server(document)
      send_edit(pid, "hello")

      stop_supervised!(DocServer)

      assert loaded_text(document.id) == "hello"
    end
  end
end
