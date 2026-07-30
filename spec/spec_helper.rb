# frozen_string_literal: true

require "rspec"
require "webmock/rspec"
require_relative "../lib/tradingview_screener"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.order = :random
  WebMock.disable_net_connect!(allow_localhost: false)
end
