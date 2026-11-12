# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in typed_bus.gemspec
gemspec

group :development, :test do
  gem "debug_me"
  gem "irb"
  gem "rake"
  gem "minitest"
  gem "simplecov", require: false
end

# Not needed by the test suite. ratatui_ruby is a Rust native extension
# used only by examples/15_performance.rb; aigcm is a local commit helper.
# Install with: bundle config set --local with extras && bundle install
group :extras, optional: true do
  gem "aigcm"
  gem "ratatui_ruby"
end
