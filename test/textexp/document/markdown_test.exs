defmodule Textexp.Document.MarkdownTest do
  use Textexp.DataCase

  alias Textexp.Document

  defp register_user do
    Textexp.Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: "markdown-#{System.unique_integer([:positive])}@example.com",
      password: "a-long-password",
      password_confirmation: "a-long-password"
    })
    |> Ash.create!(authorize?: false)
  end

  defp snapshot(text) do
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

  test "is the body of the saved snapshot", %{user: user} do
    document =
      %{title: "Notes"}
      |> Document.create_document!(actor: user)
      |> Document.save_snapshot!(snapshot("Hello"), authorize?: false)

    assert Document.document_markdown!(document) == "Hello"
    assert [%{markdown: "Hello"}] = Document.list_documents!(load: [:markdown], authorize?: false)
  end

  test "is empty without snapshot", %{user: user} do
    document = Document.create_document!(%{title: "Notes"}, actor: user)

    assert Document.document_markdown!(document) == ""
  end
end
