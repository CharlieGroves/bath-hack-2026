class DropPropertyEnrichmentsAndEmbeddings < ActiveRecord::Migration[7.2]
  def change
    drop_table :property_enrichments, if_exists: true
    drop_table :property_embeddings, if_exists: true
  end
end
