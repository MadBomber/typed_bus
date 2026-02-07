# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create(:test) do |t|
  t.libs << "test"
  t.test_prelude = 'require "test_helper"'
  t.test_globs = ["test/**/*_test.rb"]
end

task default: :test
