# frozen_string_literal: true

module TradingviewScreener
  # ActiveRecord-style model base.
  #
  #   class Stock < TradingviewScreener::Base
  #     market "america"
  #     default_scope { where(is_primary: true) }
  #     scope :liquid, -> { where(volume: gt(1_000_000)) }
  #   end
  #
  #   Stock.liquid.where(close: 10..300).order(volume: :desc).limit(20).load
  class Base
    class << self
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@scopes, {})
        subclass.instance_variable_set(:@default_scopes, [])
      end

      def market(name = nil)
        if name.nil?
          @default_market
        else
          @default_market = name.to_s
        end
      end
      alias default_market market

      def columns(*names)
        if names.empty?
          @default_columns
        else
          @default_columns = names.flatten.map(&:to_s)
        end
      end
      alias default_columns columns

      def default_limit(value = nil)
        if value.nil?
          @default_limit
        else
          @default_limit = Integer(value)
        end
      end

      def default_order_values
        @default_order
      end
      alias default_order default_order_values

      def order_by(column, direction = :desc)
        @default_order = [{ "sortBy" => column.to_s, "sortOrder" => direction.to_s == "asc" ? "asc" : "desc" }]
      end

      def default_where
        @default_where
      end

      def default_filter2
        @default_filter2
      end

      def filter2(value)
        @default_filter2 = value
      end

      def scope(name, body = nil, &block)
        callable = body || block
        raise ArgumentError, "scope needs a callable" unless callable

        scopes[name.to_sym] = callable
        define_singleton_method(name) do |*args, **kwargs|
          rel = all
          result =
            if callable.arity.nonzero? || kwargs.any?
              rel.instance_exec(*args, **kwargs, &callable)
            else
              rel.instance_exec(&callable)
            end
          result.nil? ? none : result
        end
      end

      def default_scope(body = nil, &block)
        callable = body || block
        raise ArgumentError, "default_scope needs a callable" unless callable

        default_scopes << callable
      end

      def all
        rel = Relation.new(self)
        default_scopes.reduce(rel) do |memo, callable|
          result = memo.instance_exec(&callable)
          result.nil? ? memo : result
        end
      end

      def none
        all.none
      end

      def where(...) = all.where(...)
      def rewhere(...) = all.rewhere(...)
      def select(...) = all.select(...)
      def order(...) = all.order(...)
      def limit(...) = all.limit(...)
      def offset(...) = all.offset(...)
      def market!(...) = all.market(...)
      def tickers(...) = all.tickers(...)
      def merge(...) = all.merge(...)
      def except(...) = all.except(...)
      def load(**kwargs) = all.load(**kwargs)
      def to_a(**kwargs) = all.to_a(**kwargs)
      def count(**kwargs) = all.count(**kwargs)
      def first(...) = all.first(...)
      def last(...) = all.last(...)
      def pluck(...) = all.pluck(...)
      def pick(...) = all.pick(...)
      def ids(**kwargs) = all.ids(**kwargs)
      def exists?(**kwargs) = all.exists?(**kwargs)
      def find_each(**opts, &block) = all.to_a(**opts).each(&block)

      def [](name)
        Field.new(name)
      end

      def unscoped
        Relation.new(self)
      end

      def from_payload(payload)
        Relation.from_payload(self, payload)
      end

      def from_screen_data(screen_data)
        from_payload(ScreenData.to_payload(screen_data))
      end

      def from_screener_url(url, cookies: nil, proxy: nil, timeout: 20)
        fetched = ScreenData.fetch(url, cookies: cookies, proxy: proxy, timeout: timeout)
        from_payload(fetched["payload"])
      end

      protected

      def scopes
        @scopes ||= {}
      end

      def default_scopes
        @default_scopes ||= []
      end
    end
  end

  # Convenience root model for US equities.
  class Stock < Base
    market "america"
    order_by "market_cap_basic", :desc
    default_limit 50

    default_scope do
      where(is_primary: true)
    end

    scope :primary, -> { where(is_primary: true) }

    scope :priced_between, lambda { |min, max|
      where(close: min..max)
    }

    # Captured from live MT LONG / MT SHORT TradingView screeners.
    scope :momentum_trend_long, lambda {
      select(
        "ticker-view", "close", "type", "typespecs", "pricescale", "minmov", "fractional", "minmove2",
        "currency", "change", "volume", "relative_volume_10d_calc", "market_cap_basic",
        "fundamental_currency_code", "price_earnings_ttm", "earnings_per_share_diluted_ttm",
        "earnings_per_share_diluted_yoy_growth_ttm", "dividends_yield_current", "sector.tr",
        "market", "sector", "AnalystRating", "AnalystRating.tr", "premarket_change", "premarket_volume"
      ).where(
        "AvgValue.Traded_10d" => gt(50_000_000),
        ATRP: gt(1)
      ).where(
        market_cap_basic: gte(1_000_000_000),
        premarket_volume: gt(30_000),
        "relative_volume_intraday|5" => gt(1.1),
        ATRP: lt(6),
        close: 10..300
      ).where(
        TradingviewScreener::Stock[:close].gt(TradingviewScreener::Stock[:SMA20])
      ).order(premarket_volume: :desc).limit(100)
    }

    scope :momentum_trend_short, lambda {
      select(
        "ticker-view", "close", "type", "typespecs", "pricescale", "minmov", "fractional", "minmove2",
        "currency", "change", "volume", "relative_volume_10d_calc", "market_cap_basic",
        "fundamental_currency_code", "price_earnings_ttm", "earnings_per_share_diluted_ttm",
        "earnings_per_share_diluted_yoy_growth_ttm", "dividends_yield_current", "sector.tr",
        "market", "sector", "AnalystRating", "AnalystRating.tr", "premarket_change", "premarket_volume"
      ).where(
        TradingviewScreener::Stock[:close].lt(TradingviewScreener::Stock[:SMA20]),
        "relative_volume_intraday|5" => gt(1.1),
        premarket_volume: gt(30_000),
        ATRP: lt(6)
      ).where(
        ATRP: gt(1),
        "AvgValue.Traded_10d" => gt(50_000_000),
        market_cap_basic: gte(1_000_000_000),
        close: 10..300
      ).order(market_cap_basic: :desc).limit(100)
    }

    # Captured from live MS LONG / MS SHORT TradingView screeners.
    scope :momentum_scalping_long, lambda {
      select(
        "ticker-view", "close", "type", "typespecs", "pricescale", "minmov", "fractional", "minmove2",
        "currency", "change", "volume", "relative_volume_10d_calc", "market_cap_basic",
        "fundamental_currency_code", "price_earnings_ttm", "earnings_per_share_diluted_ttm",
        "earnings_per_share_diluted_yoy_growth_ttm", "dividends_yield_current", "sector.tr",
        "market", "sector", "AnalystRating", "AnalystRating.tr", "premarket_change", "premarket_volume"
      ).where(
        close: 10..300,
        "relative_volume_intraday|5" => gt(1.1),
        ATRP: lt(6),
        market_cap_basic: gte(1_000_000_000),
        premarket_gap: gt(0.5),
        premarket_volume: gt(30_000)
      ).where(
        premarket_gap: lt(8),
        ATRP: gt(1)
      ).order(premarket_volume: :desc).limit(100)
    }

    scope :momentum_scalping_short, lambda {
      select(
        "ticker-view", "close", "type", "typespecs", "pricescale", "minmov", "fractional", "minmove2",
        "currency", "change", "volume", "relative_volume_10d_calc", "market_cap_basic",
        "fundamental_currency_code", "price_earnings_ttm", "earnings_per_share_diluted_ttm",
        "earnings_per_share_diluted_yoy_growth_ttm", "dividends_yield_current", "sector.tr",
        "market", "sector", "AnalystRating", "AnalystRating.tr", "premarket_change", "premarket_volume"
      ).where(
        premarket_gap: gt(-8),
        market_cap_basic: gte(1_000_000_000)
      ).where(
        ATRP: gt(1)
      ).where(
        ATRP: lt(6),
        premarket_volume: gt(30_000),
        "relative_volume_intraday|5" => gt(1.1),
        premarket_gap: lt(-0.5),
        close: 10..300
      ).order(premarket_volume: :desc).limit(100)
    }

    # Captured from live ORB LONG / ORB SHORT TradingView screeners.
    scope :open_range_breakout_long, lambda {
      select(
        "ticker-view", "close", "type", "typespecs", "pricescale", "minmov", "fractional", "minmove2",
        "currency", "change", "volume", "relative_volume_10d_calc", "market_cap_basic",
        "fundamental_currency_code", "price_earnings_ttm", "earnings_per_share_diluted_ttm",
        "earnings_per_share_diluted_yoy_growth_ttm", "dividends_yield_current", "sector.tr",
        "market", "sector", "AnalystRating", "AnalystRating.tr"
      ).where(
        market_cap_basic: gte(1_000_000_000),
        average_volume_10d_calc: gt(3_000_000),
        close: 10..300,
        ATRP: gt(5),
        premarket_gap: gt(2)
      ).order(market_cap_basic: :desc).limit(100)
    }

    scope :open_range_breakout_short, lambda {
      select(
        "ticker-view", "close", "type", "typespecs", "pricescale", "minmov", "fractional", "minmove2",
        "currency", "change", "volume", "relative_volume_10d_calc", "market_cap_basic",
        "fundamental_currency_code", "price_earnings_ttm", "earnings_per_share_diluted_ttm",
        "earnings_per_share_diluted_yoy_growth_ttm", "dividends_yield_current", "sector.tr",
        "market", "sector", "AnalystRating", "AnalystRating.tr"
      ).where(
        close: 10..300,
        premarket_gap: lt(-3),
        average_volume_10d_calc: gt(3_000_000),
        ATRP: gt(5),
        market_cap_basic: gte(1_000_000_000)
      ).order(market_cap_basic: :desc).limit(100)
    }
  end
end
