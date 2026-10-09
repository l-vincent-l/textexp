defmodule Textexp.Document.Writing do
  @moduledoc """
  Update Yjs incrémentale reçue pour un document depuis son dernier compactage
  (voir `Textexp.Document.Document`, attribut `snapshot`).
  """
  use Ash.Resource, otp_app: :textexp, domain: Textexp.Document, data_layer: AshSqlite.DataLayer

  sqlite do
    table "writings"
    repo Textexp.SqliteRepo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:value, :document_id]
    end

    read :for_document do
      argument :document_id, :uuid, allow_nil?: false

      filter expr(document_id == ^arg(:document_id))
      prepare build(sort: [inserted_at: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :value, :binary do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :document, Textexp.Document.Document do
      allow_nil? false
      public? true
    end
  end
end
