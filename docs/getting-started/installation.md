# Installation

## Requirements

- Ruby >= 4.0
- [async](https://github.com/socketry/async) ~> 2.0
- [logger](https://github.com/ruby/logger)

## Bundler

Add to your Gemfile:

```ruby
gem "typed_bus"
```

Then run:

```bash
bundle install
```

## Manual

```bash
gem install typed_bus
```

## Verify

```ruby
require "typed_bus"
puts TypedBus::VERSION
```
