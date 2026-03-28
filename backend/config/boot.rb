ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# Load .env from the Rails app root (not Dir.pwd), so GOOGLE_API_KEY etc. work when
# the shell cwd is not backend/ (e.g. running from the monorepo root).
require "dotenv"
env_file = File.expand_path("../.env", __dir__)
Dotenv.load(env_file) if File.file?(env_file)

require "bootsnap/setup" # Speed up boot time by caching expensive operations.
