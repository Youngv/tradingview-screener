# Changelog

## 0.2.3

### Fixed
- Saved screener `SymbolType` checkbox selections now produce the scanner's canonical `filter2` branches instead of an invalid ordinary `type in ["CommonStock"]` filter.
- Common stock, preferred stock, depositary receipt, and deterministic multi-select combinations preserve their exact TradingView semantics.
- Unknown, blank, duplicate, malformed, or multiply active `SymbolType` contracts now fail explicitly instead of widening or corrupting the scanner query.

## 0.2.2

### Fixed
- Saved screener conversion now maps TradingView camelCase comparison operations to canonical scanner tokens, including `belowOrEqual` to `eless` and `aboveOrEqual` to `egreater`.
- Saved screener `Exchange` fields now map to the scanner's canonical `exchange` field.
- Unknown saved screener operations now raise a conversion error instead of silently changing their meaning to equality.
- Saved screener URL conversion now validates filter and sort fields against the scanner's HTTP `/metainfo` contract without requiring a browser.
- Added a checked-in, development-generated base map for hundreds of TradingView UI column IDs, with explicit rules for parameterized financial and interval fields.

## 0.2.1

### Fixed
- `Relation#load` now rejects scanner responses whose `totalCount` is missing, negative, or not an integer instead of coercing invalid values to zero.

## 0.2.0

### Changed
- Gem/package name is `tradingview-screener` (RubyGems hyphen convention); require remains `tradingview_screener`.
- Extracted into a standalone publishable gem.
- Removed implicit ActiveSupport dependency (`presence` / `blank?`).
- Pure Ruby runtime: only stdlib + optional `socksify` for SOCKS proxies.
- Added a tracked Ruby version for reproducible development with RVM.
- Added strict gem validation and a Ruby 3.1-3.4 CI test matrix.
- Clarified Ruby support, unofficial API status, and the release workflow.

### Added
- ActiveRecord-style `Relation` / `Base` / scopes API.
- Built-in momentum trend, momentum scalping, and open-range breakout scopes.
- `ScreenData` parser/converter for saved TradingView screener URLs/HTML.
- HTTP and SOCKS proxy support on the scanner client.
