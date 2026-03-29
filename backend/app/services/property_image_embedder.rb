require "digest"
require "json"
require "open3"

# Runs +scripts/embed_dinov2_images.py+ (Meta DINOv2 via torch.hub). Default: +dinov2_vitb14+ (768-d CLS, L2-normalized).
# To use OpenCLIP again, point +SCRIPT_BASENAME+ at +embed_openclip_images.py+ and restore MODEL_* / payload keys.
#
# Requires: pip install -r requirements-image-embed.txt
# Optional: ENV["PYTHON_BIN"] (default +python3+).
class PropertyImageEmbedder
  # DINOv2 hub names: dinov2_vits14 (384), dinov2_vitb14 (768), dinov2_vitl14 (1024), dinov2_vitg14 (1536).
  # If you change HUB_MODEL, set EXPECTED_DIM and PropertyImageEmbedding::EXPECTED_DIMENSIONS (+ optional migration).
  HUB_MODEL = "dinov2_vitb14".freeze
  MODEL_ID = "dinov2:#{HUB_MODEL}".freeze
  EXPECTED_DIM = 768
  SCRIPT_BASENAME = "embed_dinov2_images.py".freeze

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

    script = Rails.root.join("scripts", SCRIPT_BASENAME)
    raise Error, "Missing #{script}" unless script.file?

    python = ENV.fetch("PYTHON_BIN", "python3")
    payload = {
      urls: list,
      hub_model: HUB_MODEL
    }.to_json

    stdout, stderr, status = Open3.capture3(python, script.to_s, stdin_data: payload)
    unless status.success?
      raise Error, "embed_dinov2_images failed (#{status.exitstatus}): #{stderr.presence || stdout}"
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
