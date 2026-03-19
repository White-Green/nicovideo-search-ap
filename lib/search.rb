# frozen_string_literal: true

# ref: https://site.nicovideo.jp/search-api-docs/snapshot

require "json"
require "net/http"
require "time"
require "uri"
require "dry-types"
require "dry-struct"

module SnapshotTypes
  include Dry.Types()
end

class SnapshotSuccessMeta < Dry::Struct
  transform_keys(&:to_sym)

  attribute :status, SnapshotTypes::Integer.constrained(eql: 200)
  attribute :totalCount, SnapshotTypes::Integer
  attribute :id, SnapshotTypes::String
end

class SnapshotErrorMeta < Dry::Struct
  transform_keys(&:to_sym)

  attribute :status, SnapshotTypes::Integer
  attribute :errorCode, SnapshotTypes::String
  attribute :errorMessage, SnapshotTypes::String
  attribute? :id, SnapshotTypes::String.optional
end

class SnapshotDataItem < Dry::Struct
  transform_keys(&:to_sym)

  attribute :contentId, SnapshotTypes::String
  attribute :title, SnapshotTypes::String
  attribute :startTime, SnapshotTypes::String
end

class SnapshotSuccessResponse < Dry::Struct
  transform_keys(&:to_sym)

  attribute :meta, SnapshotSuccessMeta
  attribute :data, SnapshotTypes::Array.of(SnapshotDataItem)
end

Video = Struct.new(:id, :title, :posted_at, keyword_init: true)

SEARCH_ENDPOINT = URI("https://snapshot.search.nicovideo.jp/api/v2/snapshot/video/contents/search")
DEFAULT_USER_AGENT = "White-Green/nicovideo-search-ap"
DEFAULT_CONTEXT = "White-Green/nicovideo-search-ap"
DEFAULT_FIELDS = %w[contentId title startTime].freeze
MAX_LIMIT = 100
MAX_RESULTS = 10_000
REQUEST_INTERVAL_SECONDS = 1.0

def search(query:, period_days:)
  period_days = Integer(period_days)
  raise ArgumentError, "period_days must be positive" if period_days <= 0

  query_string = Array(query).map(&:to_s).map(&:strip).join(" ")
  period_start = Time.now.utc - (period_days * 24 * 60 * 60)

  videos_by_id = {}
  offset = 0
  loop do
    snapshot = request_snapshot(
      query_string:,
      period_start:,
      offset:,
      limit: MAX_LIMIT,
    )
    items = snapshot.data
    break if items.empty?

    items.each do |item|
      posted_at = item.startTime
      content_id = item.contentId
      next if content_id.nil? || content_id.empty?

      videos_by_id[content_id] = Video.new(
        id: content_id,
        title: item.title.to_s,
        posted_at:,
      )
      break if videos_by_id.size >= MAX_RESULTS
    end

    break if videos_by_id.size >= MAX_RESULTS
    break if items.size < MAX_LIMIT

    offset += MAX_LIMIT
  end

  videos_by_id
    .values
    .sort_by do |video|
      [video.posted_at.to_s, video.id]
    end
    .reverse
end

def request_snapshot(query_string:, period_start:, offset:, limit:)
  sleep_with_jitter(REQUEST_INTERVAL_SECONDS)

  params = {
    "q" => query_string,
    "fields" => DEFAULT_FIELDS.join(","),
    "filters[startTime][gte]" => period_start.iso8601,
    "_sort" => "-startTime",
    "_offset" => offset.to_s,
    "_limit" => limit.to_s,
    "_context" => DEFAULT_CONTEXT,
  }
  params["targets"] = "tagsExact" unless query_string.empty?

  uri = SEARCH_ENDPOINT.dup
  uri.query = URI.encode_www_form(params)

  request = Net::HTTP::Get.new(uri)
  request["User-Agent"] = DEFAULT_USER_AGENT

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 30, open_timeout: 10) do |http|
    http.request(request)
  end

  begin
    SnapshotSuccessResponse[JSON.parse(response.body)]
  rescue => e
    raise "Snapshot API response validation failed: #{e.class}: #{e.message} " \
        "url=#{uri} body=#{response.body}"
  end
end

def sleep_with_jitter(base_seconds)
  return if base_seconds.zero?

  jitter = rand * 0.4
  sleep(base_seconds + jitter)
end
