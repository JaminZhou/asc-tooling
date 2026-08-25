require_relative "test_helper"

class ASCToolingIAPTest < Minitest::Test
  class FakeClient
    attr_reader :requests

    def initialize(iaps)
      @iaps = iaps
      @requests = []
    end

    def find_app!(_bundle_id)
      OpenStruct.new(id: "app-123", name: "Example", bundle_id: "com.example.app")
    end

    def request_json(method, path, params: nil, body: nil)
      @requests << { method: method, path: path, params: params, body: body }
      return { "data" => @iaps } if method == "GET" && path == "/v1/apps/app-123/inAppPurchasesV2"
      return { "data" => [] } if method == "GET" && path.end_with?("/inAppPurchaseLocalizations")
      return { "data" => nil } if method == "GET" && path.end_with?("/appStoreReviewScreenshot")
      return { "data" => nil } if method == "GET" && path.end_with?("/inAppPurchaseAvailability")

      return { "data" => { "id" => "submission-123" } } if method == "POST" && path == "/v1/inAppPurchaseSubmissions"

      raise "unexpected request: #{method} #{path}"
    end

    def api_error_codes(_payload)
      []
    end
  end

  def test_status_marks_first_iap_web_submission_requirement
    client = FakeClient.new([iap("first", state: "READY_TO_SUBMIT")])
    helper = build_iap(client)

    summary = helper.send(:status_summary)

    assert summary[:first_iap_web_submission_required]
  end

  def test_submit_stops_before_post_for_first_iap
    client = FakeClient.new([iap("first", state: "READY_TO_SUBMIT")])
    helper = build_iap(client)

    error = assert_raises(ArgumentError) do
      helper.send(:submit)
    end

    assert_includes error.message, "first in-app purchase"
    request_methods = client.requests.map { |request| request[:method] }
    assert_equal ["GET"], request_methods
  end

  def test_submit_allows_direct_submission_after_an_iap_was_approved
    client = FakeClient.new([
                              iap("approved", state: "APPROVED"),
                              iap("next", state: "READY_TO_SUBMIT")
                            ])
    helper = build_iap(client, product_ids: ["next"])

    stdout, = capture_io do
      helper.send(:submit)
    end

    request_methods = client.requests.map { |request| request[:method] }
    assert_equal %w[GET POST], request_methods
    assert_includes stdout, "Submitted next (next): submission-123"
  end

  def test_submit_is_noop_when_first_iap_is_already_waiting_for_review
    client = FakeClient.new([iap("first", state: "WAITING_FOR_REVIEW")])
    helper = build_iap(client)

    stdout, = capture_io do
      helper.send(:submit)
    end

    request_methods = client.requests.map { |request| request[:method] }
    assert_equal ["GET"], request_methods
    assert_includes stdout, "is WAITING_FOR_REVIEW; direct submission requires READY_TO_SUBMIT"
  end

  def test_status_does_not_mark_web_requirement_after_first_iap_is_already_submitted
    client = FakeClient.new([iap("first", state: "WAITING_FOR_REVIEW")])
    helper = build_iap(client)

    refute helper.send(:first_iap_web_submission_required?)
  end

  def test_first_iap_error_matching_accepts_prefix_and_message_variants
    client = FakeClient.new([])
    helper = build_iap(client)
    client.define_singleton_method(:api_error_codes) { |_payload| ["STATE_ERROR.FIRST_IAP_REQUIRES_APP_VERSION"] }
    prefixed = ASCTooling::APIError.new("submit", 409, { "errors" => [] })
    message = ASCTooling::APIError.new(
      "submit",
      409,
      { "errors" => [{ "detail" => "The first in-app purchase must be submitted with an app version." }] }
    )

    assert helper.send(:first_iap_review_error?, prefixed)
    client.define_singleton_method(:api_error_codes) { |_payload| [] }
    assert helper.send(:first_iap_review_error?, message)
  end

  private

  def build_iap(client, options = {})
    helper = ASCTooling::IAP.allocate
    helper.instance_variable_set(
      :@options,
      {
        bundle_id: "com.example.app",
        product_ids: [],
        dry_run: false
      }.merge(options)
    )
    helper.instance_variable_set(:@asc, client)
    helper
  end

  def iap(product_id, state:)
    {
      "id" => "iap-#{product_id}",
      "attributes" => {
        "productId" => product_id,
        "name" => product_id,
        "state" => state
      }
    }
  end
end
