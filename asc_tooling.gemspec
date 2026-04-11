lib_dir = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)
require "asc_tooling/version"

Gem::Specification.new do |spec|
  spec.name = "asc_tooling"
  spec.version = ASCTooling::VERSION
  spec.authors = ["Jamin Zhou"]
  spec.email = ["me@jaminzhou.com"]

  spec.summary = "Reusable App Store Connect automation tooling"
  spec.description = "Review, metadata, sales, screenshot, and beta tooling for App Store Connect workflows."
  spec.homepage = "https://github.com/JaminZhou/asc-tooling"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir.chdir(__dir__) do
    Dir["exe/*", "lib/**/*.rb", "*.gemspec", "Gemfile"]
  end
  spec.bindir = "exe"
  spec.executables = %w[
    asc-review
    asc-metadata
    asc-beta
    asc-sales
    asc-screenshots
    asc-iap
    asc-version
  ]
  spec.require_paths = ["lib"]

  spec.add_dependency "fastlane", ">= 2.220"
  spec.add_development_dependency "minitest", ">= 5.0"
end
