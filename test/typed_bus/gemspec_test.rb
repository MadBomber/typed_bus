# frozen_string_literal: true

require "test_helper"

class GemspecTest < Minitest::Test
  GEMSPEC_PATH = File.expand_path("../../typed_bus.gemspec", __dir__)
  ALLOWED = %r{\A(lib/.+\.rb|README\.md|CHANGELOG\.md|LICENSE.*)\z}

  def spec
    @spec ||= Gem::Specification.load(GEMSPEC_PATH)
  end

  def test_packages_only_library_code_and_top_level_docs
    extra = spec.files.grep_v(ALLOWED)

    assert_empty extra, "gemspec packages files outside the allowlist"
  end

  def test_packages_every_library_file
    root = File.dirname(GEMSPEC_PATH)
    lib_files = Dir.glob("lib/**/*.rb", base: root)

    assert_equal lib_files.sort, spec.files.grep(%r{\Alib/}).sort
  end

  def test_packages_readme_and_changelog
    assert_includes spec.files, "README.md"
    assert_includes spec.files, "CHANGELOG.md"
  end

  def test_has_no_executables
    assert_empty spec.executables
  end
end
