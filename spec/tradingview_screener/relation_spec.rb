# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingviewScreener::Relation do
  describe "ActiveRecord-style chaining" do
    it "builds immutable relations like AR" do
      base = TradingviewScreener::Stock.all
      priced = base.where(close: 10..300)
      ordered = priced.order(volume: :desc).limit(10)

      expect(base.to_query["filter"]).to include(
        hash_including("left" => "is_primary", "operation" => "equal", "right" => true)
      )
      expect(priced.to_query["filter"]).to include(
        hash_including("left" => "close", "operation" => "in_range", "right" => [10, 300])
      )
      expect(ordered.to_query["sort"]).to eq("sortBy" => "volume", "sortOrder" => "desc")
      expect(ordered.to_query["range"]).to eq([0, 10])
      expect(base.to_query["range"]).not_to eq([0, 10])
    end

    it "supports hash operators and field nodes" do
      rel = TradingviewScreener::Stock
        .where(volume: TradingviewScreener::Predicates.gt(1_000_000))
        .where(TradingviewScreener::Stock[:close].gt(TradingviewScreener::Stock[:SMA20]))

      expect(rel.to_query["filter"]).to include(
        hash_including("left" => "volume", "operation" => "greater", "right" => 1_000_000),
        hash_including("left" => "close", "operation" => "greater", "right" => "SMA20")
      )
    end

    it "supports scopes and default_scope" do
      rel = TradingviewScreener::Stock.priced_between(10, 50).limit(5)
      expect(rel.to_query["filter"]).to include(
        hash_including("left" => "is_primary", "right" => true),
        hash_including("left" => "close", "operation" => "in_range", "right" => [10, 50])
      )
    end

    it "loads rows via scanner API" do
      stub_request(:post, %r{scanner\.tradingview\.com/america/scan})
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            totalCount: 2,
            data: [
              { "s" => "NASDAQ:NVDA", "d" => ["NVDA", 120.0] },
              { "s" => "NYSE:T", "d" => ["T", 20.0] }
            ]
          }.to_json
        )

      rel = TradingviewScreener::Stock.select("name", "close").limit(2).load
      expect(rel.size).to eq(2)
      expect(rel.ids).to eq(%w[NASDAQ:NVDA NYSE:T])
      expect(rel.pluck("name")).to eq(%w[NVDA T])
      expect(rel.first["close"]).to eq(120.0)
    end

    it "rejects scanner responses without totalCount" do
      stub_request(:post, %r{scanner\.tradingview\.com/america/scan})
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { data: [] }.to_json
        )

      expect { TradingviewScreener::Stock.limit(1).load }
        .to raise_error(TradingviewScreener::Error, /totalCount/)
    end

    it "rejects scanner responses with an invalid totalCount" do
      stub_request(:post, %r{scanner\.tradingview\.com/america/scan})
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { totalCount: "unknown", data: [] }.to_json
        )

      expect { TradingviewScreener::Stock.limit(1).load }
        .to raise_error(TradingviewScreener::Error, /totalCount/)
    end

    it "rejects scanner responses with a negative totalCount" do
      stub_request(:post, %r{scanner\.tradingview\.com/america/scan})
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { totalCount: -1, data: [] }.to_json
        )

      expect { TradingviewScreener::Stock.limit(1).load }
        .to raise_error(TradingviewScreener::Error, /totalCount/)
    end

    it "exposes momentum scopes with long/short direction" do
      long = TradingviewScreener::Stock.momentum_trend_long
      short = TradingviewScreener::Stock.momentum_trend_short

      expect(long.to_query["filter"]).to include(
        hash_including("left" => "close", "operation" => "greater", "right" => "SMA20")
      )
      expect(short.to_query["filter"]).to include(
        hash_including("left" => "close", "operation" => "less", "right" => "SMA20")
      )
      expect(long.to_query["sort"]["sortBy"]).to eq("premarket_volume")
      expect(short.to_query["sort"]["sortBy"]).to eq("market_cap_basic")
    end

    it "exposes momentum scalping and open range breakout scopes" do
      ms_long = TradingviewScreener::Stock.momentum_scalping_long
      ms_short = TradingviewScreener::Stock.momentum_scalping_short
      orb_long = TradingviewScreener::Stock.open_range_breakout_long
      orb_short = TradingviewScreener::Stock.open_range_breakout_short

      expect(ms_long.to_query["filter"]).to include(
        hash_including("left" => "premarket_gap", "operation" => "greater", "right" => 0.5),
        hash_including("left" => "premarket_gap", "operation" => "less", "right" => 8)
      )
      expect(ms_short.to_query["filter"]).to include(
        hash_including("left" => "premarket_gap", "operation" => "less", "right" => -0.5),
        hash_including("left" => "premarket_gap", "operation" => "greater", "right" => -8)
      )
      expect(orb_long.to_query["filter"]).to include(
        hash_including("left" => "premarket_gap", "operation" => "greater", "right" => 2),
        hash_including("left" => "ATRP", "operation" => "greater", "right" => 5)
      )
      expect(orb_short.to_query["filter"]).to include(
        hash_including("left" => "premarket_gap", "operation" => "less", "right" => -3),
        hash_including("left" => "average_volume_10d_calc", "operation" => "greater", "right" => 3_000_000)
      )
      expect(ms_long.to_query["sort"]["sortBy"]).to eq("premarket_volume")
      expect(orb_long.to_query["sort"]["sortBy"]).to eq("market_cap_basic")
    end
  end
end
