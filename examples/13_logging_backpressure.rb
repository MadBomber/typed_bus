#!/usr/bin/env ruby
# frozen_string_literal: true

# 13 — Logging with Backpressure
#
# Demonstrates log output when a bounded channel applies backpressure.
# The publisher fiber blocks when max_pending is reached, then resumes
# as subscribers drain the queue. Watch the DEBUG-level backpressure
# messages interleave with publish/ack logs.

require "logger"
require_relative "../lib/typed_bus"

logger = Logger.new($stdout)
logger.level = Logger::DEBUG
logger.formatter = proc do |severity, datetime, _progname, msg|
  timestamp = datetime.strftime("%H:%M:%S.%L")
  color = case severity
          when "WARN"  then "\e[33m"
          when "ERROR" then "\e[31m"
          when "DEBUG" then "\e[36m"
          when "INFO"  then "\e[32m"
          else "\e[0m"
          end
  "#{color}#{timestamp} [#{severity.ljust(5)}]\e[0m #{msg}\n"
end

TypedBus.logger = logger

channel = TypedBus::Channel.new(
  :pipeline,
  type: Integer,
  timeout: 2,
  max_pending: 2
)

# Slow subscriber — takes 0.15s per message
channel.subscribe do |delivery|
  sleep 0.15
  delivery.ack!
end

Async do
  5.times do |i|
    puts "--- Publisher: sending message #{i + 1} ---"
    channel.publish(i + 1)
  end

  sleep 0.5 # let remaining deliveries settle
  puts
  puts "All messages processed."
  channel.close
end

# Clean up
TypedBus.logger = nil
