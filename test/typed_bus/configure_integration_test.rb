# frozen_string_literal: true

require "test_helper"

class ConfigureIntegrationTest < Minitest::Test
  def setup
    TypedBus.reset_configuration!
  end

  def teardown
    TypedBus.reset_configuration!
  end

  # --- Global configure block ---

  def test_configure_sets_global_defaults
    TypedBus.configure do |c|
      c.timeout     = 60
      c.max_pending = 500
      c.throttle    = 0.5
    end

    assert_equal 60,  TypedBus.configuration.timeout
    assert_equal 500, TypedBus.configuration.max_pending
    assert_in_delta 0.5, TypedBus.configuration.throttle
  end

  def test_configure_sets_logger
    logger = Logger.new($stdout)
    TypedBus.configure { |c| c.logger = logger }

    assert_same logger, TypedBus.logger
  end

  def test_configure_sets_log_level
    logger = Logger.new($stdout)
    TypedBus.configure do |c|
      c.logger    = logger
      c.log_level = Logger::DEBUG
    end

    assert_equal Logger::DEBUG, logger.level
  end

  # --- configuration= setter ---

  def test_configuration_setter_replaces_global
    custom = TypedBus::Configuration.new
    custom.timeout = 77
    TypedBus.configuration = custom

    assert_same custom, TypedBus.configuration
    assert_equal 77, TypedBus.configuration.timeout
  end

  # --- reset_configuration! ---

  def test_reset_configuration_restores_defaults
    TypedBus.configure do |c|
      c.timeout   = 999
      c.log_level = Logger::FATAL
    end
    TypedBus.reset_configuration!

    assert_equal 30, TypedBus.configuration.timeout
    assert_nil TypedBus.configuration.logger
    assert_equal Logger::INFO, TypedBus.configuration.log_level
  end

  # --- Logger shortcuts ---

  def test_logger_shortcut_reads_from_configuration
    logger = Logger.new($stdout)
    TypedBus.configuration.logger = logger

    assert_same logger, TypedBus.logger
  end

  def test_logger_shortcut_writes_to_configuration
    logger = Logger.new($stdout)
    TypedBus.logger = logger

    assert_same logger, TypedBus.configuration.logger
  end

  # --- Global → Bus cascade ---

  def test_bus_inherits_global_timeout
    TypedBus.configure { |c| c.timeout = 60 }
    bus = TypedBus::MessageBus.new

    assert_equal 60, bus.config.timeout
  end

  def test_bus_overrides_global_timeout
    TypedBus.configure { |c| c.timeout = 60 }
    bus = TypedBus::MessageBus.new(timeout: 10)

    assert_equal 10, bus.config.timeout
  end

  def test_bus_inherits_global_max_pending
    TypedBus.configure { |c| c.max_pending = 500 }
    bus = TypedBus::MessageBus.new

    assert_equal 500, bus.config.max_pending
  end

  def test_bus_overrides_global_max_pending_with_nil
    TypedBus.configure { |c| c.max_pending = 500 }
    bus = TypedBus::MessageBus.new(max_pending: nil)

    assert_nil bus.config.max_pending
  end

  def test_bus_inherits_global_throttle
    TypedBus.configure { |c| c.throttle = 0.5 }
    bus = TypedBus::MessageBus.new

    assert_in_delta 0.5, bus.config.throttle
  end

  def test_bus_overrides_global_throttle
    TypedBus.configure { |c| c.throttle = 0.5 }
    bus = TypedBus::MessageBus.new(throttle: 0.0)

    assert_in_delta 0.0, bus.config.throttle
  end

  # --- Bus → Channel cascade (verified via timeout behavior) ---

  def test_channel_inherits_bus_timeout_via_auto_nack
    bus = TypedBus::MessageBus.new(timeout: 0.02)
    bus.add_channel(:q) # inherits 0.02s timeout
    bus.subscribe(:q) { |_d| } # never acks

    Async do
      bus.publish(:q, "msg")
      sleep(0.08)
    end

    assert_equal 1, bus.stats[:q_timed_out]
  end

  def test_channel_overrides_bus_timeout
    bus = TypedBus::MessageBus.new(timeout: 60)
    bus.add_channel(:fast, timeout: 0.02)
    bus.subscribe(:fast) { |_d| } # never acks

    Async do
      bus.publish(:fast, "msg")
      sleep(0.08)
    end

    assert_equal 1, bus.stats[:fast_timed_out]
  end

  # --- Full three-tier: Global → Bus → Channel ---

  def test_three_tier_cascade_config_values
    TypedBus.configure do |c|
      c.timeout     = 120
      c.max_pending = 1000
      c.throttle    = 0.8
    end

    # Bus overrides timeout only
    bus = TypedBus::MessageBus.new(timeout: 45)
    assert_equal 45,   bus.config.timeout
    assert_equal 1000, bus.config.max_pending
    assert_in_delta 0.8, bus.config.throttle
  end

  def test_three_tier_channel_inherits_bus_defaults
    TypedBus.configure { |c| c.timeout = 0.02 }
    bus = TypedBus::MessageBus.new  # inherits 0.02s
    bus.add_channel(:inherited)     # inherits 0.02s
    bus.subscribe(:inherited) { |_d| }

    Async do
      bus.publish(:inherited, "msg")
      sleep(0.08)
    end

    assert_equal 1, bus.stats[:inherited_timed_out]
  end

  def test_three_tier_channel_overrides_bus
    TypedBus.configure { |c| c.timeout = 120 }
    bus = TypedBus::MessageBus.new(timeout: 60)
    bus.add_channel(:custom, timeout: 0.02)
    bus.subscribe(:custom) { |_d| }

    Async do
      bus.publish(:custom, "msg")
      sleep(0.08)
    end

    assert_equal 1, bus.stats[:custom_timed_out]
  end

  # --- Bus config isolation ---

  def test_bus_config_does_not_mutate_global
    TypedBus.configure { |c| c.timeout = 60 }
    TypedBus::MessageBus.new(timeout: 5)

    assert_equal 60, TypedBus.configuration.timeout
  end

  def test_two_buses_are_independent
    bus_a = TypedBus::MessageBus.new(timeout: 10)
    bus_b = TypedBus::MessageBus.new(timeout: 99)

    assert_equal 10, bus_a.config.timeout
    assert_equal 99, bus_b.config.timeout
  end

  # --- TB alias ---

  def test_tb_alias
    assert_same TypedBus, TB
  end
end
