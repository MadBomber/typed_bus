# frozen_string_literal: true

require "test_helper"

class TypedBusTest < Minitest::Test
  def test_has_a_version_number
    refute_nil TypedBus::VERSION
  end

  def test_logger_defaults_to_nil
    original = TypedBus.logger
    TypedBus.logger = nil
    assert_nil TypedBus.logger
  ensure
    TypedBus.logger = original
  end

  def test_logger_can_be_assigned
    original = TypedBus.logger
    logger = Logger.new(StringIO.new)
    TypedBus.logger = logger
    assert_equal logger, TypedBus.logger
  ensure
    TypedBus.logger = original
  end
end
