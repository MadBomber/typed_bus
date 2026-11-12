# frozen_string_literal: true

require "test_helper"

class GemspecTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  ALLOWED = %r{\A(lib/.+\.rb|README\.md|CHANGELOG\.md|LICENSE.*)\z}

  def spec
    Gem::Specification.load(File.join(ROOT, "typed_bus.gemspec")).tap { |loaded| refute_nil loaded, "typed_bus.gemspec failed to load" }
  end

  def tracked_files
    IO.popen(%w[git ls-files -z], chdir: ROOT, &:read).split("\x0")
  end

  def test_packages_exactly_the_tracked_library_code_and_top_level_docs
    assert_equal tracked_files.grep(ALLOWED).sort, spec.files.sort
  end

  def test_packages_entry_point_readme_and_changelog
    %w[lib/typed_bus.rb README.md CHANGELOG.md].each { |path| assert_includes spec.files, path }
  end
end
