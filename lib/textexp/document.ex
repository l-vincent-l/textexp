defmodule Textexp.Document do
  use Ash.Domain,
    otp_app: :textexp,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Textexp.Document.Writing do
      define :add_writing, action: :create, args: [:document_id, :value]
      define :list_writings, action: :for_document, args: [:document_id]
    end

    resource Textexp.Document.Document do
      define :create_document, action: :create
      define :get_document, action: :read, get_by: [:id]
      define :list_documents, action: :read
      define :rename_document, action: :rename, args: [:title]
      define :compact_document, action: :compact, args: [:snapshot, :until]
    end
  end
end
