# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @config = TypedBus::Configuration.new
  end

  # --- Factory defaults ---

  def test_default_timeout
    assert_equal 30, @config.timeout
  end

  def test_default_max_pending
    assert_nil @config.max_pending
  end

  def test_default_throttle
    assert_in_delta 0.0, @config.throttle
  end

  def test_default_logger
    assert_nil @config.logger
  end

  def test_default_log_level
    assert_equal Logger::INFO, @config.log_level
  end

  # --- Setters ---

  def test_set_timeout
    @config.timeout = 60
    assert_equal 60, @config.timeout
  end

  def test_set_max_pending
    @config.max_pending = 200
    assert_equal 200, @config.max_pending
  end

  def test_set_throttle
    @config.throttle = 0.75
    assert_in_delta 0.75, @config.throttle
  end

  def test_set_logger
    logger = Logger.new($stdout)
    @config.logger = logger
    assert_same logger, @config.logger
  end

  def test_set_log_level
    @config.log_level = Logger::DEBUG
    assert_equal Logger::DEBUG, @config.log_level
  end

  # --- log_level / logger interaction ---

  def test_setting_logger_applies_current_log_level
    @config.log_level = Logger::WARN
    logger = Logger.new($stdout)
    @config.logger = logger

    assert_equal Logger::WARN, logger.level
  end

  def test_setting_log_level_applies_to_current_logger
    logger = Logger.new($stdout)
    @config.logger = logger
    @config.log_level = Logger::DEBUG

    assert_equal Logger::DEBUG, logger.level
  end

  def test_setting_log_level_without_logger_does_not_raise
    @config.log_level = Logger::ERROR
    assert_equal Logger::ERROR, @config.log_level
  end

  # --- dup independence ---

  def test_dup_creates_independent_copy
    @config.timeout = 60
    copy = @config.dup

    copy.timeout = 10
    assert_equal 60, @config.timeout
    assert_equal 10, copy.timeout
  end

  def test_dup_shares_logger
    logger = Logger.new($stdout)
    @config.logger = logger
    copy = @config.dup

    assert_same logger, copy.logger
  end

  # --- resolve ---

  def test_resolve_inherits_all_when_use_default
    @config.timeout     = 45
    @config.max_pending = 100
    @config.throttle    = 0.5

    result = @config.resolve
    assert_equal({ timeout: 45, max_pending: 100, throttle: 0.5 }, result)
  end

  def test_resolve_overrides_timeout
    result = @config.resolve(timeout: 5)
    assert_equal 5, result[:timeout]
    assert_nil result[:max_pending]
    assert_in_delta 0.0, result[:throttle]
  end

  def test_resolve_overrides_max_pending
    result = @config.resolve(max_pending: 50)
    assert_equal 30, result[:timeout]
    assert_equal 50, result[:max_pending]
  end

  def test_resolve_overrides_throttle
    result = @config.resolve(throttle: 0.8)
    assert_in_delta 0.8, result[:throttle]
  end

  def test_resolve_explicit_nil_overrides_non_nil
    @config.max_pending = 500
    result = @config.resolve(max_pending: nil)
    assert_nil result[:max_pending]
  end

  def test_resolve_multiple_overrides
    result = @config.resolve(timeout: 10, max_pending: 200, throttle: 0.3)
    assert_equal({ timeout: 10, max_pending: 200, throttle: 0.3 }, result)
  end

  # --- DEFAULTS constant ---

  def test_defaults_frozen
    assert TypedBus::Configuration::DEFAULTS.frozen?
  end
end
