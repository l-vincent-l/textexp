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
    YPersistence.bind(nil, document_id, doc)
    doc |> Yex.Doc.get_text("t") |> Yex.Text.to_string()
  end

  setup do
    %{document: Document.create_document!(%{}, actor: register_user())}
  end

  test "loading a document does not write anything", %{document: document} do
    YPersistence.update_v1(nil, text_update("hello"), document.id, nil)

    assert loaded_text(document.id) == "hello"
    assert length(Document.list_writings!(document.id)) == 1
  end

  test "unbind compacts the writings into the snapshot", %{document: document} do
    YPersistence.update_v1(nil, text_update("hello"), document.id, nil)

    doc = Yex.Doc.new()
    YPersistence.bind(nil, document.id, doc)
    YPersistence.unbind(nil, document.id, doc)

    assert Document.list_writings!(document.id) == []
    assert Document.get_document!(document.id).snapshot
    assert loaded_text(document.id) == "hello"
  end

  test "starting a DocServer does not re-persist the loaded content", %{document: document} do
    YPersistence.update_v1(nil, text_update("hello"), document.id, nil)

    {:ok, pid} =
      DocServer.start(topic: "y_doc_room:#{document.id}", doc_name: document.id)

    # the load-time update message is handled before this call returns
    _ = :sys.get_state(pid)

    assert length(Document.list_writings!(document.id)) == 1

    ref = Process.monitor(pid)
    GenServer.stop(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end
end
