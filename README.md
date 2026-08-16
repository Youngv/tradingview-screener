# tradingview-screener

[![Gem Version](https://img.shields.io/gem/v/tradingview-screener.svg)](https://rubygems.org/gems/tradingview-screener)

ActiveRecord-style Ruby client for TradingView's scanner API.

Inspired by [shner-elmo/TradingView-Screener](https://github.com/shner-elmo/TradingView-Screener), but designed like Rails ORM relations — not a Python port.

This is an unofficial client and is not affiliated with or endorsed by TradingView. The scanner endpoints are not a guaranteed public API and may change without notice.

Gem name uses hyphens (`tradingview-screener`); the require path and module use underscores:

```ruby
require "tradingview_screener"
# also works: require "tradingview/screener"  # Bundler default for hyphen gems
TradingviewScreener::Stock
```

If Bundler does not load it automatically, set:

```ruby
gem "tradingview-screener", require: "tradingview_screener"
```

## Install

Ruby 3.1 or newer is required.

### From a local path

```ruby
# Gemfile
gem "tradingview-screener", path: "../tradingview-screener"
```

### From RubyGems

```ruby
# Gemfile
gem "tradingview-screener", "~> 0.2"
```

```bash
gem install tradingview-screener
```

SOCKS proxies are optional. If you need them:

```ruby
gem "socksify", "~> 1.7"
```

## Quick start

```ruby
require "tradingview_screener"

rows = TradingviewScreener::Stock
  .where(close: 10..300)
  .where(volume: TradingviewScreener::Predicates.gt(1_000_000))
  .where(TradingviewScreener::Stock[:close].gt(TradingviewScreener::Stock[:SMA20]))
  .order(volume: :desc)
  .limit(20)
  .to_a

rows.first["ticker"]  # => "NASDAQ:NVDA"
```

## ORM-shaped API

| ActiveRecord | tradingview-screener |
|---|---|
| `Model.where(a: 1)` | `Stock.where(is_primary: true)` |
| `where(price: 10..20)` | `where(close: 10..300)` |
| `where(status: %w[a b])` | `where(type: %w[stock fund])` |
| `order(created_at: :desc)` | `order(premarket_volume: :desc)` |
| `limit` / `offset` | same |
| `select(:id, :name)` | `select("name", "close")` |
| `scope :active, -> { ... }` | same |
| `default_scope` | same |
| `all` / `to_a` / `count` / `pluck` / `first` | same |
| relation is immutable chain | same |

### Operators

```ruby
where(volume: TradingviewScreener::Predicates.gt(1_000_000))
where(market_cap_basic: TradingviewScreener::Predicates.gte(1_000_000_000))
where(ATRP: TradingviewScreener::Predicates.lt(6))

# Arel-like nodes
where(TradingviewScreener::Stock[:close].gt(TradingviewScreener::Stock[:SMA20]))
where(TradingviewScreener::Stock[:typespecs].has(["common"]))
```

### Scopes

```ruby
class MyScreen < TradingviewScreener::Base
  market "america"
  default_scope { where(is_primary: true) }

  scope :liquid, -> {
    where("AvgValue.Traded_10d" => TradingviewScreener::Predicates.gt(50_000_000))
  }
  scope :wide_atr, -> {
    where(ATRP: TradingviewScreener::Predicates.gt(1))
      .where(ATRP: TradingviewScreener::Predicates.lt(6))
  }
end

MyScreen.liquid.wide_atr.order(volume: :desc).limit(50).load
```

### Built-in momentum scopes

```ruby
TradingviewScreener::Stock.momentum_trend_long.to_a
TradingviewScreener::Stock.momentum_trend_short.ids
TradingviewScreener::Stock.momentum_scalping_long.to_a
TradingviewScreener::Stock.open_range_breakout_short.ids
```

### Saved screener URL / screen_data

```ruby
rel = TradingviewScreener::Stock.from_screener_url(
  "https://www.tradingview.com/screener/YOUR_SCREEN_ID/",
  cookies: {
    "sessionid" => ENV.fetch("TRADINGVIEW_SESSIONID"),
    "sessionid_sign" => ENV.fetch("TRADINGVIEW_SESSIONID_SIGN")
  }
)
rel.to_a
```

`from_screener_url` uses server-side HTTP only: it reads `screen_data` from the saved screener HTML,
fetches each selected market's scanner `/metainfo`, and validates filter/sort fields before building the
relation. It does not require a browser or browser-captured requests.

If `screen_data` is already available, validate it explicitly with the same HTTP contract:

```ruby
payload = TradingviewScreener::ScreenData.to_validated_payload(screen_data)
rel = TradingviewScreener::Stock.from_payload(payload)
```

Saved Stock Screener `SymbolType` checkbox values are structural filters. The converter maps Common stock,
Preferred stock, and Depositary receipt selections into the scanner's canonical `filter2`; it does not emit
them as ordinary `type` filters. Multiple selected types become a deterministic OR expression, while unknown,
blank, duplicate, malformed, or multiply active SymbolType contracts raise `ScreenData::ConversionError`.
An inactive SymbolType checkbox continues to use the scanner's default stock-type contract.

Callers processing many screeners may fetch and reuse a `ScreenData::FieldContract`; passing a contract
to `to_payload` keeps conversion deterministic and avoids repeated HTTP requests. Unknown operations and
fields fail fast. Projection-only scanner aliases are not validated because TradingView omits them from
`/metainfo`; filter and sort fields are always validated.

The production request path never downloads or executes TradingView JavaScript bundles. Bundle inspection
may be used as a development-time drift signal, but explicit reviewed mappings remain the runtime contract.

The checked-in generated base map covers hundreds of current TradingView UI column IDs. Refresh candidates
during development with `ruby script/update_screen_data_column_map`, review the diff, and run the metainfo
contract tests before committing it. Parameterized fields continue to use hand-written semantic rules.

### Cookies / proxy

```ruby
TradingviewScreener::Stock.momentum_trend_long.load(
  cookies: {
    "sessionid" => ENV.fetch("TRADINGVIEW_SESSIONID"),
    "sessionid_sign" => ENV.fetch("TRADINGVIEW_SESSIONID_SIGN")
  },
  proxy: "http://user:pass@127.0.0.1:7890"
)
```

## Debugging

```ruby
rel = TradingviewScreener::Stock
  .where(TradingviewScreener::Stock[:close].gt(TradingviewScreener::Stock[:SMA20]))
  .limit(10)

puts rel.to_sql      # JSON payload sent to scanner
puts rel.scanner_url
```

## Development

```bash
bundle install
bundle exec rspec
bundle exec rake build   # => pkg/tradingview-screener-0.2.3.gem
gem build tradingview-screener.gemspec --strict
```

Before publishing, verify that the version is not already in use and inspect the package:

```bash
gem build tradingview-screener.gemspec --strict
gem contents --show-install-dir tradingview-screener # after installing the built gem
gem push tradingview-screener-0.2.3.gem
```

RubyGems MFA is required for releases. Source code and issue tracking are available on [GitHub](https://github.com/Youngv/tradingview-screener).

## License

MIT
