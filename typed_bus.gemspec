# frozen_string_literal: true

require_relative "lib/typed_bus/version"

Gem::Specification.new do |spec|
  spec.name = "typed_bus"
  spec.version = TypedBus::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dewayne@vanhoozer.me"]

  spec.summary = "Async pub/sub message bus with typed channels, ACK-based delivery, and dead letter queues"
  spec.description = <<~DESC
    A lightweight async message bus built on the async gem with fiber-only concurrency.
    Provides typed pub/sub channels with explicit acknowledgment, dead letter queues,
    bounded backpressure, delivery timeout tracking, and per-channel statistics.
  DESC
  spec.homepage = "https://github.com/MadBomber/typed_bus"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Allowlist of tracked files to package. :(glob) keeps * from crossing /.
  packaged = %w[:(glob)lib/**/*.rb :(glob)README.md :(glob)CHANGELOG.md :(glob)LICENSE*]
  spec.files = IO.popen(["git", "ls-files", "-z", "--", *packaged], chdir: __dir__, err: IO::NULL, &:read).split("\x0")
  spec.require_paths = ["lib"]

  spec.add_dependency "async", "~> 2.0"
  spec.add_dependency "logger"
end
