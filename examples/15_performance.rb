#!/usr/bin/env ruby
# frozen_string_literal: true

# 15 — Pure Performance Demo (TUI Dashboard)
#
# Runs multiple independent MessageBus instances, each with its own
# channel/publisher/subscriber configuration.  Subscribers immediately
# ack every delivery so the bottleneck is the bus machinery itself.
# Timeouts are disabled (nil) to avoid creating a timeout fiber per
# delivery, which at high throughput would cause RSS to grow unbounded.
#
# Uses ratatui_ruby for a live terminal dashboard with gauges, sparklines,
# a stats table, and a throughput bar chart.  Includes live memory
# monitoring (RSS + GC stats) for leak detection.
#
# Press q or Ctrl-C to stop.
#
# Usage:
#   bundle exec ruby examples/15_performance.rb

require_relative "../lib/typed_bus"
require "ratatui_ruby"
require "csv"

# ---------------------------------------------------------------------------
# Bus configurations
# ---------------------------------------------------------------------------

BUS_CONFIGS = [
  { name: "A", channels: 2, publishers: 3, subscribers: 2 },
  { name: "B", channels: 3, publishers: 4, subscribers: 4 },
  { name: "C", channels: 1, publishers: 6, subscribers: 8 },
].freeze

COLORS = [:green, :cyan, :magenta].freeze

# ---------------------------------------------------------------------------
# Per-bus runtime state (mutable counters shared across threads)
# ---------------------------------------------------------------------------

BusState = Struct.new(
  :name, :config, :bus, :channel_names, :color,
  :published, :acked, :prev_acked, :rate_history
)

def build_buses
  BUS_CONFIGS.each_with_index.map do |cfg, idx|
    bus       = TypedBus::MessageBus.new(timeout: nil)
    ch_names  = cfg[:channels].times.map { |i| :"#{cfg[:name].downcase}_#{i}" }
    ch_names.each { |ch| bus.add_channel(ch, timeout: nil) }

    BusState.new(cfg[:name], cfg, bus, ch_names, COLORS[idx],
                 0, 0, 0, [])
  end
end

# ---------------------------------------------------------------------------
# TypedBus workload — runs in a background Thread inside an Async reactor
# ---------------------------------------------------------------------------

def start_workload(buses, stop_flag)
  Thread.new do
    Async do |task|
      buses.each do |s|
        s.channel_names.each do |ch|
          s.config[:subscribers].times do
            s.bus.subscribe(ch) do |delivery|
              s.acked += 1
              delivery.ack!
            end
          end
        end

        s.channel_names.each do |ch|
          s.config[:publishers].times do
            task.async do
              seq = 0
              until stop_flag[]
                s.bus.publish(ch, seq)
                s.published += 1
                seq += 1
                Async::Task.current.yield
              end
            end
          end
        end
      end

      sleep(0.05) until stop_flag[]
    end

    buses.each { |s| s.bus.close_all }
  end
end

# ---------------------------------------------------------------------------
# Memory sampler — reads RSS from the OS, GC stats from the runtime
# ---------------------------------------------------------------------------

class MemorySampler
  HISTORY_SIZE = 120

  # Classes to count via ObjectSpace.each_object (sampled every 2s)
  TRACKED_CLASSES = {
    "Delivery" => TypedBus::Delivery,
    "Tracker"  => TypedBus::DeliveryTracker,
  }.freeze

  attr_reader :rss_kb, :rss_history, :baseline_rss_kb,
              :heap_live, :total_allocated, :total_freed,
              :gc_count, :gc_major_count,
              :object_counts, :object_deltas

  def initialize
    @pid              = Process.pid
    @rss_kb           = read_rss
    @baseline_rss_kb  = @rss_kb
    @rss_history      = [@rss_kb]
    @last_rss_sample  = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @last_obj_sample  = @last_rss_sample
    @object_counts    = {}
    @object_deltas    = {}
    @baseline_objects = nil
    sample_gc
    sample_objects
  end

  def sample(now)
    if (now - @last_rss_sample) >= 1.0
      @last_rss_sample = now
      @rss_kb = read_rss
      @rss_history << @rss_kb
      @rss_history.shift if @rss_history.size > HISTORY_SIZE
      sample_gc
    end

    if (now - @last_obj_sample) >= 2.0
      @last_obj_sample = now
      sample_objects
    end
  end

  def rss_mb      = (@rss_kb / 1024.0).round(1)
  def baseline_mb = (@baseline_rss_kb / 1024.0).round(1)

  def delta_mb
    ((@rss_kb - @baseline_rss_kb) / 1024.0).round(1)
  end

  private

  def read_rss
    `ps -o rss= -p #{@pid}`.strip.to_i
  end

  def sample_gc
    st = GC.stat
    @heap_live        = st[:heap_live_slots]
    @total_allocated  = st[:total_allocated_objects]
    @total_freed      = st[:total_freed_objects]
    @gc_count         = st[:count]
    @gc_major_count   = st[:major_gc_count]
  end

  def sample_objects
    counts = {}
    TRACKED_CLASSES.each { |label, klass| counts[label] = ObjectSpace.each_object(klass).count }
    counts["Task"]  = ObjectSpace.each_object(Async::Task).count
    counts["Fiber"] = ObjectSpace.each_object(Fiber).count
    counts["Proc"]  = ObjectSpace.each_object(Proc).count
    @object_counts = counts
    @baseline_objects ||= counts.dup
    @object_deltas = counts.each_with_object({}) { |(k, v), h| h[k] = v - @baseline_objects[k] }
  end
end

# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------

def fmt(n)
  n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
end

# ---------------------------------------------------------------------------
# TUI Application
# ---------------------------------------------------------------------------

class PerfDashboard
  SPARKLINE_WIDTH = 120

  CSV_PATH = "perf_metrics.csv"
  CSV_INTERVAL = 5.0  # seconds between CSV rows

  def initialize
    @buses         = build_buses
    @stop_flag     = -> { @stopping }
    @stopping      = false
    @start_time    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @tick          = 0
    @last_sample   = @start_time
    @last_csv      = @start_time
    @total_history = []
    @mem           = MemorySampler.new
    @csv_file      = open_csv
    @worker        = start_workload(@buses, @stop_flag)
  end

  def run
    RatatuiRuby.run do |tui|
      @tui = tui
      loop do
        sample_rates
        maybe_write_csv
        draw
        break if handle_input == :quit
      end
      @stopping = true
      @worker.join(2)
      @csv_file.close
    end
  end

  private

  # ---- Data sampling -------------------------------------------------------

  def sample_rates
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @mem.sample(now)

    dt = now - @last_sample
    return if dt < 0.25

    @last_sample = now
    @tick += 1
    total_rate = 0

    @buses.each do |s|
      cur      = s.acked
      interval = cur - s.prev_acked
      rate     = (interval / dt).round(0)
      s.prev_acked = cur
      s.rate_history << rate
      s.rate_history.shift if s.rate_history.size > SPARKLINE_WIDTH
      total_rate += rate
    end

    @total_history << total_rate
    @total_history.shift if @total_history.size > SPARKLINE_WIDTH
  end

  def elapsed
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time
  end

  # ---- Layout --------------------------------------------------------------
  #
  #  Row 0:  Title                                           (3)
  #  Row 1:  [ Bus A gauge ] [ Bus B gauge ] [ Bus C gauge ] (6)
  #  Row 2:  [ Throughput sparkline ] | [ RSS sparkline ]    (fill)
  #  Row 3:  [ Live Objects ]        | [ GC & Internals ]   (7)
  #  Row 4:  Totals bar + footer key                         (3)
  #

  def draw
    @tui.draw do |frame|
      rows = @tui.layout_split(
        frame.area,
        direction: :vertical,
        constraints: [
          @tui.constraint_length(3),   # title
          @tui.constraint_length(6),   # bus gauges (side-by-side)
          @tui.constraint_fill(1),     # sparklines (expand)
          @tui.constraint_length(7),   # object diagnostics + GC/bus internals
          @tui.constraint_length(3),   # totals + footer
        ]
      )

      render_title(frame, rows[0])
      render_bus_row(frame, rows[1])
      render_sparklines_row(frame, rows[2])
      render_bottom_row(frame, rows[3])
      render_totals(frame, rows[4])
    end
  end

  # ---- Widgets -------------------------------------------------------------

  def render_title(frame, area)
    frame.render_widget(
      @tui.paragraph(
        text: "TypedBus Performance Dashboard",
        alignment: :center,
        block: @tui.block(
          borders: [:all],
          border_style: @tui.style(fg: :blue),
        )
      ),
      area
    )
  end

  # -- Bus gauges: three panels side-by-side ---------------------------------

  def render_bus_row(frame, area)
    cols = @tui.layout_split(
      area,
      direction: :horizontal,
      constraints: @buses.map { @tui.constraint_fill(1) }
    )
    @buses.each_with_index { |s, i| render_bus_panel(frame, cols[i], s) }
  end

  def render_bus_panel(frame, area, bus)
    cfg      = bus.config
    cur_rate = bus.rate_history.last || 0
    avg      = bus.acked > 0 ? (bus.acked / elapsed).round(0) : 0

    # Gauge ratio: relative to the highest bus
    max_rate = @buses.map { |b| b.rate_history.last || 1 }.max
    max_rate = 1 if max_rate == 0
    ratio    = [cur_rate.to_f / max_rate, 1.0].min

    # Split: gauge on top, stats underneath
    gauge_area, stats_area = @tui.layout_split(
      area,
      direction: :vertical,
      constraints: [
        @tui.constraint_length(3),
        @tui.constraint_fill(1),
      ]
    )

    gauge = @tui.gauge(
      ratio: ratio,
      label: "#{fmt(cur_rate)}/s",
      gauge_style: @tui.style(fg: bus.color),
      block: @tui.block(
        title: "Bus #{bus.name}  #{cfg[:channels]}ch x #{cfg[:publishers]}pub x #{cfg[:subscribers]}sub",
        borders: [:all],
        border_style: @tui.style(fg: bus.color),
      )
    )
    frame.render_widget(gauge, gauge_area)

    stats = @tui.paragraph(
      text: [
        @tui.text_line(spans: [
          @tui.text_span(content: " pub ", style: @tui.style(fg: :dark_gray)),
          @tui.text_span(content: fmt(bus.published)),
          @tui.text_span(content: "  ack ", style: @tui.style(fg: :dark_gray)),
          @tui.text_span(content: fmt(bus.acked)),
          @tui.text_span(content: "  avg ", style: @tui.style(fg: :dark_gray)),
          @tui.text_span(content: "#{fmt(avg)}/s"),
        ]),
      ]
    )
    frame.render_widget(stats, stats_area)
  end

  # -- Sparklines: throughput left, RSS right --------------------------------

  def render_sparklines_row(frame, area)
    left, right = @tui.layout_split(
      area,
      direction: :horizontal,
      constraints: [
        @tui.constraint_fill(1),
        @tui.constraint_fill(1),
      ]
    )
    render_throughput_sparkline(frame, left)
    render_rss_sparkline(frame, right)
  end

  def render_throughput_sparkline(frame, area)
    data = @total_history.empty? ? [0] : @total_history
    frame.render_widget(
      @tui.sparkline(
        data: data,
        style: @tui.style(fg: :yellow),
        block: @tui.block(
          title: "Throughput (ack/s)",
          borders: [:all],
          border_style: @tui.style(fg: :yellow),
        )
      ),
      area
    )
  end

  def render_rss_sparkline(frame, area)
    data = @mem.rss_history.empty? ? [0] : @mem.rss_history
    delta_sign = @mem.delta_mb >= 0 ? "+" : ""
    delta_color = @mem.delta_mb.abs > 5.0 ? :red : :green
    delta_str = "#{delta_sign}#{@mem.delta_mb}"

    frame.render_widget(
      @tui.sparkline(
        data: data,
        style: @tui.style(fg: :red),
        block: @tui.block(
          title: "RSS #{@mem.rss_mb} MB  (base #{@mem.baseline_mb}, \u0394#{delta_str} MB)",
          borders: [:all],
          border_style: @tui.style(fg: :red),
        )
      ),
      area
    )
  end

  # -- Bottom row: object diagnostics left, GC + bus internals right --------

  def render_bottom_row(frame, area)
    left, right = @tui.layout_split(
      area,
      direction: :horizontal,
      constraints: [
        @tui.constraint_fill(1),
        @tui.constraint_fill(1),
      ]
    )
    render_object_counts(frame, left)
    render_gc_and_internals(frame, right)
  end

  def render_object_counts(frame, area)
    lines = @mem.object_counts.map do |label, count|
      delta = @mem.object_deltas[label] || 0
      delta_sign = delta >= 0 ? "+" : ""
      delta_color = delta > 100 ? :red : :green

      @tui.text_line(spans: [
        @tui.text_span(content: " #{label.ljust(10)}", style: @tui.style(fg: :dark_gray)),
        @tui.text_span(content: fmt(count).rjust(10)),
        @tui.text_span(content: "  "),
        @tui.text_span(
          content: "#{delta_sign}#{fmt(delta)}".rjust(10),
          style: @tui.style(fg: delta_color),
        ),
      ])
    end

    frame.render_widget(
      @tui.paragraph(
        text: lines,
        block: @tui.block(
          title: "Live Objects (count / \u0394 from start)",
          borders: [:all],
          border_style: @tui.style(fg: :yellow),
        )
      ),
      area
    )
  end

  def render_gc_and_internals(frame, area)
    delta_sign  = @mem.delta_mb >= 0 ? "+" : ""
    delta_color = @mem.delta_mb.abs > 5.0 ? :red : :green

    # Bus internal state: pending deliveries + DLQ sizes
    bus_spans = @buses.flat_map do |s|
      pending = s.channel_names.sum { |ch| s.bus.pending_count(ch) }
      dlq     = s.channel_names.sum { |ch| s.bus.dead_letters(ch).size }
      pending_color = pending > 0 ? :red : :green
      dlq_color     = dlq > 0 ? :red : :green
      [
        @tui.text_span(content: " #{s.name}:", style: @tui.style(fg: s.color)),
        @tui.text_span(content: "pend=", style: @tui.style(fg: :dark_gray)),
        @tui.text_span(content: fmt(pending), style: @tui.style(fg: pending_color)),
        @tui.text_span(content: " dlq=", style: @tui.style(fg: :dark_gray)),
        @tui.text_span(content: fmt(dlq), style: @tui.style(fg: dlq_color)),
      ]
    end

    frame.render_widget(
      @tui.paragraph(
        text: [
          @tui.text_line(spans: [
            @tui.text_span(content: " Heap: ", style: @tui.style(fg: :dark_gray)),
            @tui.text_span(content: fmt(@mem.heap_live)),
            @tui.text_span(content: "  GC: ", style: @tui.style(fg: :dark_gray)),
            @tui.text_span(content: "#{@mem.gc_count} (#{@mem.gc_major_count} major)"),
          ]),
          @tui.text_line(spans: [
            @tui.text_span(content: " Alloc: ", style: @tui.style(fg: :dark_gray)),
            @tui.text_span(content: fmt(@mem.total_allocated)),
            @tui.text_span(content: "  Freed: ", style: @tui.style(fg: :dark_gray)),
            @tui.text_span(content: fmt(@mem.total_freed)),
          ]),
          @tui.text_line(spans: [
            @tui.text_span(content: " RSS \u0394: ", style: @tui.style(fg: :dark_gray)),
            @tui.text_span(
              content: "#{delta_sign}#{@mem.delta_mb} MB from baseline",
              style: @tui.style(fg: delta_color, modifiers: [:bold]),
            ),
          ]),
          @tui.text_line(spans: bus_spans),
        ],
        block: @tui.block(
          title: "GC & Bus Internals",
          borders: [:all],
          border_style: @tui.style(fg: :red),
        )
      ),
      area
    )
  end

  # -- Totals + footer -------------------------------------------------------

  def render_totals(frame, area)
    total_pub  = @buses.sum(&:published)
    total_ack  = @buses.sum(&:acked)
    total_rate = @total_history.last || 0
    avg_rate   = total_ack > 0 ? (total_ack / elapsed).round(0) : 0
    el         = elapsed.round(1)

    frame.render_widget(
      @tui.paragraph(
        text: [
          @tui.text_line(spans: [
            @tui.text_span(content: " pub: ", style: @tui.style(fg: :dark_gray)),
            @tui.text_span(content: fmt(total_pub), style: @tui.style(fg: :white, modifiers: [:bold])),
            @tui.text_span(content: "   ack: ", style: @tui.style(fg: :dark_gray)),
            @tui.text_span(content: fmt(total_ack), style: @tui.style(fg: :white, modifiers: [:bold])),
            @tui.text_span(content: "   current: ", style: @tui.style(fg: :dark_gray)),
            @tui.text_span(content: "#{fmt(total_rate)}/s", style: @tui.style(fg: :green, modifiers: [:bold])),
            @tui.text_span(content: "   avg: ", style: @tui.style(fg: :dark_gray)),
            @tui.text_span(content: "#{fmt(avg_rate)}/s", style: @tui.style(fg: :green)),
            @tui.text_span(content: "   elapsed: ", style: @tui.style(fg: :dark_gray)),
            @tui.text_span(content: "#{el}s"),
            @tui.text_span(content: "   rss: ", style: @tui.style(fg: :dark_gray)),
            @tui.text_span(content: "#{@mem.rss_mb} MB"),
          ]),
        ],
        block: @tui.block(
          titles: [
            { content: " q: Quit ", position: :bottom, alignment: :right },
          ],
          borders: [:all],
          border_style: @tui.style(fg: :blue),
        )
      ),
      area
    )
  end

  # ---- CSV logging ---------------------------------------------------------

  CSV_HEADERS = %w[
    elapsed_s rss_mb delta_mb heap_live total_allocated total_freed
    gc_count gc_major_count
    delivery tracker task fiber proc
    delivery_delta tracker_delta task_delta fiber_delta proc_delta
    total_published total_acked ack_rate_per_s
    bus_a_pending bus_a_dlq bus_b_pending bus_b_dlq bus_c_pending bus_c_dlq
  ].freeze

  def open_csv
    file = File.open(CSV_PATH, "w")
    file.puts(CSV_HEADERS.join(","))
    file
  end

  def maybe_write_csv
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return if (now - @last_csv) < CSV_INTERVAL

    @last_csv = now

    bus_internals = @buses.flat_map do |s|
      pending = s.channel_names.sum { |ch| s.bus.pending_count(ch) }
      dlq     = s.channel_names.sum { |ch| s.bus.dead_letters(ch).size }
      [pending, dlq]
    end

    row = [
      elapsed.round(1),
      @mem.rss_mb,
      @mem.delta_mb,
      @mem.heap_live,
      @mem.total_allocated,
      @mem.total_freed,
      @mem.gc_count,
      @mem.gc_major_count,
      @mem.object_counts["Delivery"]  || 0,
      @mem.object_counts["Tracker"]   || 0,
      @mem.object_counts["Task"]      || 0,
      @mem.object_counts["Fiber"]     || 0,
      @mem.object_counts["Proc"]      || 0,
      @mem.object_deltas["Delivery"]  || 0,
      @mem.object_deltas["Tracker"]   || 0,
      @mem.object_deltas["Task"]      || 0,
      @mem.object_deltas["Fiber"]     || 0,
      @mem.object_deltas["Proc"]      || 0,
      @buses.sum(&:published),
      @buses.sum(&:acked),
      @total_history.last || 0,
      *bus_internals,
    ]

    @csv_file.puts(row.join(","))
    @csv_file.flush
  end

  # ---- Input ---------------------------------------------------------------

  def handle_input
    case @tui.poll_event
    in { type: :key, code: "q" } | { type: :key, code: "c", modifiers: ["ctrl"] }
      :quit
    else
      nil
    end
  end
end

PerfDashboard.new.run
