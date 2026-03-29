require "digest"
require "json"
require "open3"

# Runs +scripts/embed_mpnet.py+ (Sentence Transformers) to produce a vector for the configured model.
# Default: +sentence-transformers/all-MiniLM-L6-v2+ (384-d, L2-normalized in the Python script).
#
# Requires Python 3 with: pip install -r requirements-embed.txt
# Override interpreter: ENV["PYTHON_BIN"] (default +python3+).
class PropertyDescriptionEmbedder
  MODEL_ID = "sentence-transformers/all-MiniLM-L6-v2".freeze
  EXPECTED_DIM = 384

  class Error < StandardError; end

  # @return [Array<Float>]
  def self.embed_text!(text)
    new.embed_text!(text)
  end

  # @return [String] hex SHA256 of normalized description (for change detection)
  def self.fingerprint_for(text)
    Digest::SHA256.hexdigest(text.to_s.strip)
  end

  def embed_text!(text)
    t = text.to_s.strip
    raise Error, "description is blank" if t.blank?

    script = Rails.root.join("scripts", "embed_mpnet.py")
    raise Error, "Missing #{script}" unless script.file?

    python = ENV.fetch("PYTHON_BIN", "python3")
    payload = { text: t, model: MODEL_ID }.to_json

    stdout, stderr, status = Open3.capture3(python, script.to_s, stdin_data: payload)
    raise Error, "embed script failed (#{status.exitstatus}): #{stderr.presence || stdout}" unless status.success?

    data = JSON.parse(stdout)
    raise Error, data["error"] if data["error"].present?

    vec = data["embedding"]
    raise Error, "empty embedding" if vec.blank?

    unless vec.size == EXPECTED_DIM
      raise Error, "expected #{EXPECTED_DIM} dims, got #{vec.size}"
    end

    vec.map(&:to_f)
  end
end
