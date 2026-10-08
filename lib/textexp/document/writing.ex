defmodule Textexp.Document.Writing do
  use Ash.Resource, otp_app: :textexp, domain: Textexp.Document, data_layer: AshSqlite.DataLayer

  # postgres do
  #   table "writings"
  #   repo Textexp.Repo
  # end

  sqlite do
    table "writings"
    repo Textexp.SqliteRepo
  end

  actions do
    create :create do
      accept [:value, :version, :doc_name]
    end

    read :get_updates do
      argument :doc_name, :string

      prepare build(sort: [inserted_at: :desc])
      filter expr(doc_name == ^arg(:doc_name) and version == :v1)
    end

    read :get_state_vector do
      argument :doc_name, :string

      prepare build(sort: [inserted_at: :desc])
      filter expr(doc_name == ^arg(:doc_name) and version == :v1_sv)
    end

    defaults [:read, :destroy]
  end

  attributes do
    uuid_primary_key :id

    attribute :value, :binary do
      allow_nil? false
      public? true
    end

    attribute :version, Textexp.Document.Writing.Version

    attribute :doc_name, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end
end
