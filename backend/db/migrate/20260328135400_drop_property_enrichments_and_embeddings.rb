class DropPropertyEnrichmentsAndEmbeddings < ActiveRecord::Migration[7.2]
  def change
    drop_table :property_enrichments
    drop_table :property_embeddings
  end
end
