# frozen_string_literal: true

require_relative "lib/tradingview_screener/version"

Gem::Specification.new do |spec|
  spec.name = "tradingview-screener"
  spec.version = TradingviewScreener::VERSION
  spec.authors = ["Victor Yang"]
  spec.email = ["ootyoungtoo@gmail.com"]

  spec.summary = "ActiveRecord-style Ruby client for TradingView scanner/screener API"
  spec.description = <<~DESC
    Chainable Query/Column API for TradingView's scanner endpoints.
    Inspired by shner-elmo/TradingView-Screener, designed like Rails ORM relations.
  DESC
  spec.homepage = "https://rubygems.org/gems/tradingview-screener"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "documentation_uri" => "https://www.rubydoc.info/gems/tradingview-screener",
    "allowed_push_host" => "https://rubygems.org",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib}/**/*", "LICENSE.txt", "README.md", "CHANGELOG.md"].select { |f| File.file?(f) }
  end
  spec.require_paths = ["lib"]

  # Optional at runtime for SOCKS proxies: gem "socksify"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "webmock", "~> 3.23"
  spec.add_development_dependency "socksify", "~> 1.7"
  spec.add_development_dependency "rake", "~> 13.0"
end
