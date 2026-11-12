# frozen_string_literal: true

require "test_helper"

class GemspecTest < Minitest::Test
  SPEC = Gem::Specification.load(File.expand_path("../../typed_bus.gemspec", __dir__))
  ALLOWED = %r{\A(lib/.+\.rb|README\.md|CHANGELOG\.md|LICENSE.*)\z}

  def test_packages_only_library_code_and_top_level_docs
    assert_empty SPEC.files.grep_v(ALLOWED), "gemspec packages files outside the allowlist"
  end

  def test_packages_entry_point_readme_and_changelog
    %w[lib/typed_bus.rb lib/typed_bus/version.rb README.md CHANGELOG.md].each do |path|
      assert_includes SPEC.files, path
    end
  end
end
