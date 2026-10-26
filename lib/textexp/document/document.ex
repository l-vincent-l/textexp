defmodule Textexp.Document.Document do
  @moduledoc """
  A collaborative document.

  Its Yjs content is stored in `snapshot`: the full state, rewritten at most
  every 10 s while it is being edited (see `Textexp.Document.YPersistence`).
  `excerpt` holds the first lines of its body, saved along with the snapshot to
  preview the document without decoding it. The snapshot is rewritten on each
  save, so `updated_at` is its last update (renaming also changes it).

  `role` is the reader's right on it, read along with it (see
  `Textexp.Document.get_document/2`); `snippet`, the fragment of its body
  matching a search (see `Textexp.Document.Search`).
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "documents" do
    field :title, :string
    field :snapshot, :binary
    field :excerpt, :string
    field :role, Ecto.Enum, values: [:owner, :editor, :viewer], virtual: true
    field :snippet, :any, virtual: true
    belongs_to :owner, Textexp.Accounts.User
    has_many :memberships, Textexp.Document.Membership
    timestamps(type: :utc_datetime_usec)
  end
end
