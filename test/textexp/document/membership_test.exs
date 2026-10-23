defmodule Textexp.Document.MembershipTest do
  use Textexp.DataCase

  alias Textexp.Document

  defp register_user do
    Textexp.Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: "member-#{System.unique_integer([:positive])}@example.com",
      password: "a-long-password",
      password_confirmation: "a-long-password"
    })
    |> Ash.create!(authorize?: false)
  end

  setup do
    owner = register_user()
    %{owner: owner, document: Document.create_document!(%{title: "Notes"}, actor: owner)}
  end

  describe "share_document" do
    test "gives an editor the right to read and write", %{owner: owner, document: document} do
      editor = register_user()

      assert {:ok, %{role: :editor}} =
               Document.share_document(document.id, editor.email, :editor, actor: owner)

      assert {:ok, document} = Document.get_document(document.id, actor: editor)
      assert Ash.can?({document, :rename}, editor)
    end

    test "gives a viewer the right to read only", %{owner: owner, document: document} do
      viewer = register_user()
      Document.share_document!(document.id, viewer.email, :viewer, actor: owner)

      assert {:ok, document} = Document.get_document(document.id, actor: viewer)
      refute Ash.can?({document, :rename}, viewer)
    end

    test "changes the role of a member", %{owner: owner, document: document} do
      member = register_user()
      Document.share_document!(document.id, member.email, :viewer, actor: owner)
      Document.share_document!(document.id, to_string(member.email), :editor, actor: owner)

      assert [%{role: :editor}] = Document.list_document_members!(document.id, actor: owner)
    end

    test "finds the user whatever the case of the address", %{owner: owner, document: document} do
      member = register_user()
      email = member.email |> to_string() |> String.upcase()

      assert {:ok, _} = Document.share_document(document.id, email, :viewer, actor: owner)
    end

    test "refuses an address without account", %{owner: owner, document: document} do
      assert {:error, error} =
               Document.share_document(document.id, "nobody@example.com", :viewer, actor: owner)

      assert Exception.message(error) =~ "aucun compte avec cette adresse"
    end

    test "refuses the owner's own address", %{owner: owner, document: document} do
      assert {:error, error} =
               Document.share_document(document.id, owner.email, :editor, actor: owner)

      assert Exception.message(error) =~ "propriétaire"
    end

    test "is reserved to the owner", %{owner: owner, document: document} do
      editor = register_user()
      Document.share_document!(document.id, editor.email, :editor, actor: owner)

      assert {:error, %Ash.Error.Forbidden{}} =
               Document.share_document(document.id, register_user().email, :editor, actor: editor)
    end

    test "leaves the document's last update unchanged", %{owner: owner, document: document} do
      before = Document.get_document!(document.id, load: [:last_update], actor: owner)
      Document.share_document!(document.id, register_user().email, :viewer, actor: owner)
      after_share = Document.get_document!(document.id, load: [:last_update], actor: owner)

      assert after_share.last_update == before.last_update
    end
  end

  describe "list_document_members" do
    test "lists the members to the owner, not to others", %{owner: owner, document: document} do
      member = register_user()
      Document.share_document!(document.id, member.email, :viewer, actor: owner)

      assert [%{user_id: user_id}] = Document.list_document_members!(document.id, actor: owner)
      assert user_id == member.id
      assert Document.list_document_members!(document.id, actor: register_user()) == []
    end
  end

  describe "remove_document_member" do
    test "takes the access back", %{owner: owner, document: document} do
      member = register_user()
      membership = Document.share_document!(document.id, member.email, :viewer, actor: owner)

      assert :ok = Document.remove_document_member(membership, actor: owner)
      assert {:error, _} = Document.get_document(document.id, actor: member)
    end

    test "is reserved to the owner", %{owner: owner, document: document} do
      member = register_user()
      membership = Document.share_document!(document.id, member.email, :editor, actor: owner)

      assert {:error, %Ash.Error.Forbidden{}} =
               Document.remove_document_member(membership, actor: member)
    end
  end
end
