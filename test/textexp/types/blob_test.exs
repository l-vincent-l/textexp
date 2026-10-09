defmodule Textexp.Types.BlobTest do
  use Textexp.DataCase

  alias Textexp.Document

  # Valid UTF-8 containing a NUL byte: stored as TEXT and truncated at the NUL
  # by ecto_libsql without `Textexp.Types.Blob`.
  @utf8_with_nul <<"abc", 0, "def">>

  setup do
    user =
      Textexp.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "blob-#{System.unique_integer([:positive])}@example.com",
        password: "a-long-password",
        password_confirmation: "a-long-password"
      })
      |> Ash.create!(authorize?: false)

    %{document: Document.create_document!(%{}, actor: user)}
  end

  test "snapshots keep UTF-8 binaries containing NUL bytes intact", %{document: document} do
    Document.save_snapshot!(document, @utf8_with_nul)

    assert Document.get_document!(document.id).snapshot == @utf8_with_nul
  end
end
