defmodule Textexp.Document.ImportTest do
  use Textexp.DataCase

  alias Textexp.Document

  defp register_user do
    Textexp.Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: "import-#{System.unique_integer([:positive])}@example.com",
      password: "a-long-password",
      password_confirmation: "a-long-password"
    })
    |> Ash.create!(authorize?: false)
  end

  # The Yjs state of a BlockNote document holding one paragraph.
  defp state(text) do
    doc = Yex.Doc.new()

    doc
    |> Yex.Doc.get_xml_fragment("document-store")
    |> Yex.XmlFragment.push(
      Yex.XmlElementPrelim.new("blockGroup", [
        Yex.XmlElementPrelim.new("blockContainer", [
          Yex.XmlElementPrelim.new("paragraph", [Yex.XmlTextPrelim.from(text)])
        ])
      ])
    )

    Yex.encode_state_as_update!(doc)
  end

  setup do
    %{user: register_user()}
  end

  test "creates the document with its content and excerpt", %{user: user} do
    assert {:ok, document} = Document.import_document("Recette", state("Des crêpes"), actor: user)

    assert document.title == "Recette"
    assert document.owner_id == user.id
    assert document.excerpt == "Des crêpes"
    assert Document.document_markdown!(document) == "Des crêpes"
  end

  test "refuses a state that is not Yjs", %{user: user} do
    assert {:error, error} = Document.import_document("Bad", <<1, 2, 3>>, actor: user)
    assert Exception.message(error) =~ "contenu illisible"
  end

  test "refuses a too large state", %{user: user} do
    assert {:error, error} =
             Document.import_document("Big", :binary.copy("x", 5_000_001), actor: user)

    assert Exception.message(error) =~ "trop volumineux"
  end

  test "needs an actor, the document's owner" do
    assert {:error, _} = Document.import_document("Recette", state("x"))
  end
end
