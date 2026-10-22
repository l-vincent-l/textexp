defmodule Textexp.Document.Membership do
  use Ash.Resource,
    otp_app: :textexp,
    domain: Textexp.Document,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "memberships"
    repo Textexp.SqliteRepo

    # A document or a user deleted takes its memberships along, e.g. an empty
    # document deleted when left (see YPersistence.unbind).
    references do
      reference :document, on_delete: :delete
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, create: [:role, :document_id, :user_id]]
  end

  actions do
    defaults [:read, :destroy, create: [:role, :document_id, :user_id]]
  end

  attributes do
    uuid_primary_key :id
    attribute :role, :atom, constraints: [one_of: [:editor, :viewer]], allow_nil?: false
  end

  relationships do
    belongs_to :document, Textexp.Document.Document, allow_nil?: false
    belongs_to :user, Textexp.Accounts.User, allow_nil?: false
  end

  identities do
    identity :unique_member, [:document_id, :user_id]
  end
end
