# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module TradingviewScreener
  class Error < StandardError; end

  class RequestError < Error
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      super(message)
      @status = status
      @body = body
    end
  end

  class Client
    DEFAULT_HEADERS = {
      "accept" => "application/json, text/plain, */*; q=0.01",
      "content-type" => "text/plain;charset=UTF-8",
      "origin" => "https://www.tradingview.com",
      "referer" => "https://www.tradingview.com/",
      "user-agent" => "tradingview-screener-rb/#{VERSION}"
    }.freeze

    attr_reader :timeout, :cookies, :headers, :label_product, :proxy

    def initialize(timeout: 20, cookies: nil, headers: nil, label_product: "screener-stock", proxy: nil)
      @timeout = timeout
      @cookies = normalize_cookies(cookies)
      @headers = DEFAULT_HEADERS.merge(stringify_keys(headers || {}))
      @label_product = label_product
      @proxy = normalize_proxy(proxy)
    end

    def get(url)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      headers.each { |key, value| request[key] = value }
      # HTML pages prefer browser-like accept; keep caller override if provided.
      cookie = cookie_header
      request["cookie"] = cookie unless cookie.nil? || cookie.empty?

      response = perform(uri, request)
      body = response.body.to_s
      unless response.is_a?(Net::HTTPSuccess)
        raise RequestError.new(
          "request failed: HTTP #{response.code} #{response.message}",
          status: response.code.to_i,
          body: body
        )
      end
      body
    end

    def post(url, payload)
      uri = build_uri(url)
      request = Net::HTTP::Post.new(uri)
      headers.each { |key, value| request[key] = value }
      cookie = cookie_header
      request["cookie"] = cookie unless cookie.nil? || cookie.empty?
      request.body = JSON.generate(payload)

      response = perform(uri, request)
      body = response.body.to_s
      unless response.is_a?(Net::HTTPSuccess)
        raise RequestError.new(
          "scanner request failed: HTTP #{response.code} #{response.message}",
          status: response.code.to_i,
          body: body
        )
      end

      JSON.parse(body)
    rescue JSON::ParserError => e
      raise RequestError.new("invalid scanner JSON: #{e.message}", status: response&.code&.to_i, body: body)
    end

    def perform(uri, request)
      if socks_proxy?
        request_via_socks(uri, request)
      else
        build_http(uri).request(request)
      end
    end

    private

    def build_uri(url)
      uri = URI(url)
      if label_product && !label_product.empty? && !uri.query.to_s.include?("label-product=")
        params = URI.decode_www_form(uri.query.to_s) + [["label-product", label_product]]
        uri.query = URI.encode_www_form(params)
      end
      uri
    end

    def build_http(uri)
      http =
        if http_proxy?
          Net::HTTP::Proxy(
            proxy["host"],
            proxy["port"],
            proxy["username"],
            proxy["password"]
          ).new(uri.host, uri.port)
        else
          Net::HTTP.new(uri.host, uri.port)
        end
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout
      http.read_timeout = timeout
      http
    end

    def request_via_socks(uri, request)
      require "socksify/http"
      http = Net::HTTP.SOCKSProxy(proxy["host"], proxy["port"]).new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout
      http.read_timeout = timeout
      http.request(request)
    rescue LoadError
      raise Error, "socks proxy requires the socksify gem; add gem 'socksify' and bundle install"
    end

    def cookie_header
      return if cookies.nil? || cookies.empty?

      cookies.map { |key, value| "#{key}=#{value}" }.join("; ")
    end

    def normalize_cookies(value)
      case value
      when nil then {}
      when Hash then stringify_keys(value)
      when String
        value.split(";").each_with_object({}) do |part, memo|
          key, val = part.strip.split("=", 2)
          next if key.nil? || key.empty? || val.nil?

          memo[key] = val
        end
      else
        raise ArgumentError, "cookies must be Hash or Cookie header String"
      end
    end

    def normalize_proxy(value)
      case value
      when nil, ""
        nil
      when Hash
        hash = stringify_keys(value)
        scheme = (hash["scheme"] || hash["type"] || hash["value"] || "http").to_s.downcase
        host = first_present(hash["host"], hash["hostname"], hash.dig("extra", "host"))
        port = first_present(hash["port"], hash.dig("extra", "port"))
        username = first_present(hash["username"], hash["user"], hash.dig("extra", "username"), hash.dig("extra", "id"))
        password = first_present(hash["password"], hash["pass"], hash.dig("extra", "password"), hash.dig("extra", "secret"))
        return nil if blank?(host) || blank?(port)

        {
          "scheme" => scheme,
          "host" => host.to_s,
          "port" => port.to_i,
          "username" => username,
          "password" => password
        }.compact
      when String
        uri = URI.parse(value)
        {
          "scheme" => (blank?(uri.scheme) ? "http" : uri.scheme).to_s.downcase,
          "host" => uri.host,
          "port" => uri.port,
          "username" => uri.user,
          "password" => uri.password
        }.compact
      else
        raise ArgumentError, "proxy must be Hash, URL String, or nil"
      end
    end

    def http_proxy?
      proxy && %w[http https].include?(proxy["scheme"].to_s)
    end

    def socks_proxy?
      proxy && proxy["scheme"].to_s.start_with?("socks")
    end

    def stringify_keys(hash)
      hash.each_with_object({}) { |(k, v), memo| memo[k.to_s] = v }
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?) || (value.is_a?(String) && value.strip.empty?)
    end

    def first_present(*values)
      values.find { |value| !blank?(value) }
    end
  end
end
