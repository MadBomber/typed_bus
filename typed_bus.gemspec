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

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "async", "~> 2.0"
end
