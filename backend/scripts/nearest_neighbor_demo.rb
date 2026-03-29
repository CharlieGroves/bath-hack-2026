# frozen_string_literal: true
# Pick a random row with a pgvector embedding and print its nearest neighbors.
#
#   bin/rails runner scripts/nearest_neighbor_demo.rb
#   LIMIT=15 bin/rails runner scripts/nearest_neighbor_demo.rb

limit = ENV.fetch("LIMIT", "10").to_i
seed = PropertyImageEmbedding.where.not(embedding_vector: nil).order(Arel.sql("RANDOM()")).first

unless seed
  warn "No rows with embedding_vector. Apply migration 20260329100000 and ensure embeddings are backfilled."
  exit 1
end

q = seed.query_vector
unless q
  warn "Seed row has no usable vector (expected 768 dimensions)."
  exit 1
end

hits = PropertyImageEmbedding
         .nearest_to(q, limit: limit + 1, distance: "cosine")
         .where.not(id: seed.id)
         .limit(limit)

puts "Seed: id=#{seed.id} property_id=#{seed.property_id} position=#{seed.position}"
puts "Top #{hits.size} neighbors (cosine distance — lower is more similar):"
hits.each do |r|
  puts "  id=#{r.id} property_id=#{r.property_id} position=#{r.position} distance=#{r.neighbor_distance}"
end
