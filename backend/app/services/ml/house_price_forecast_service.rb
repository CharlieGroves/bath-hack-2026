require "json"
require "open3"

module Ml
  class HousePriceForecastService
    ROOT_DIR = Rails.root.join("..").expand_path
    ML_ROOT = ROOT_DIR.join("ml-training")
    ARTIFACTS_DIR = ML_ROOT.join("artifacts", "latest")
    INFERENCE_SCRIPT = ML_ROOT.join("infer_property.py")

    def initialize(property)
      @property = property
    end

    def call
      return nil unless ready?

      stdout, stderr, status = Open3.capture3(
        python_executable,
        INFERENCE_SCRIPT.to_s,
        "--artifacts-dir",
        ARTIFACTS_DIR.to_s,
        stdin_data: JSON.generate(PropertyMachineLearningPayloadBuilder.new(@property).as_json)
      )

      unless status.success?
        Rails.logger.warn("ML inference failed for property #{@property.id}: #{stderr.presence || stdout}")
        return nil
      end

      JSON.parse(stdout)
    rescue StandardError => e
      Rails.logger.warn("ML inference exception for property #{@property.id}: #{e.class}: #{e.message}")
      nil
    end

    private

    def ready?
      INFERENCE_SCRIPT.exist? &&
        ARTIFACTS_DIR.join("model.pt").exist? &&
        ARTIFACTS_DIR.join("preprocessor.pkl").exist? &&
        ARTIFACTS_DIR.join("metadata.json").exist?
    end

    def python_executable
      return ENV["ML_PYTHON_BIN"] if ENV["ML_PYTHON_BIN"].present?
      return "/opt/anaconda3/bin/python3" if File.exist?("/opt/anaconda3/bin/python3")

      "python3"
    end
  end
end
