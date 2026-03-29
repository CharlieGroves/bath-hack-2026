require "digest"
require "json"
require "open3"

# Runs +scripts/embed_openclip_images.py+ (OpenCLIP) for ViT-L/14 image embeddings (768-d).
#
# Requires: pip install -r requirements-image-embed.txt
# Optional: ENV["PYTHON_BIN"] (default +python3+).
class PropertyImageEmbedder
  MODEL_NAME = "ViT-L-14".freeze
  PRETRAINED = "laion2b_s32b_b82k".freeze
  MODEL_ID = "open_clip:#{MODEL_NAME}:#{PRETRAINED}".freeze
  EXPECTED_DIM = 768

  class Error < StandardError; end

  # @param urls [Array<String>]
  # @return [Array<Array<Float>|nil>] one entry per URL; nil if that image failed
  def self.embed_urls!(urls)
    new.embed_urls!(urls)
  end

  def self.fingerprint_for_slot(position, url)
    Digest::SHA256.hexdigest("#{MODEL_ID}:#{position}:#{url}")
  end

  def embed_urls!(urls)
    list = Array(urls).map(&:to_s).map(&:strip).reject(&:blank?)
    return [] if list.empty?

    script = Rails.root.join("scripts", "embed_openclip_images.py")
    raise Error, "Missing #{script}" unless script.file?

    python = ENV.fetch("PYTHON_BIN", "python3")
    payload = {
      urls: list,
      model: MODEL_NAME,
      pretrained: PRETRAINED
    }.to_json

    stdout, stderr, status = Open3.capture3(python, script.to_s, stdin_data: payload)
    unless status.success?
      raise Error, "embed_openclip_images failed (#{status.exitstatus}): #{stderr.presence || stdout}"
    end

    data = JSON.parse(stdout)
    raise Error, data["error"] if data["error"].present?

    embs = data["embeddings"]
    raise Error, "unexpected embeddings length" unless embs.is_a?(Array) && embs.size == list.size

    dim = data["dimensions"].to_i
    raise Error, "expected #{EXPECTED_DIM} dims, got #{dim}" if dim != EXPECTED_DIM && dim.positive?

    embs.map do |row|
      next nil if row.nil?

      vec = row.map(&:to_f)
      raise Error, "bad vector length #{vec.size}" unless vec.size == EXPECTED_DIM

      vec
    end
  end
end
