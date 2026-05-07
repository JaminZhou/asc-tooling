require_relative "test_helper"

class ASCToolingReviewTest < Minitest::Test
  FakeVersion = Struct.new(:id, :version_string, :app_store_state, keyword_init: true)

  class FakeClient
    attr_reader :deleted_resources, :find_version_calls, :requests

    def initialize(app:, versions:)
      @app = app
      @versions = versions.dup
      @deleted_resources = []
      @find_version_calls = []
      @requests = []
    end

    def platform(_value)
      "MAC_OS"
    end

    def find_app!(_bundle_id)
      @app
    end

    def find_version!(_app, platform:, app_version: nil, states: nil)
      @find_version_calls << {
        platform: platform,
        app_version: app_version,
        states: states
      }
      @versions.shift || raise("no fake version queued")
    end

    def request_json(method, path, params: nil, body: nil)
      @requests << {
        method: method,
        path: path,
        params: params,
        body: body
      }
      { "data" => { "id" => "release-request-123" } }
    end

    def delete_resource(path)
      @deleted_resources << path
      {}
    end
  end

  def test_release_creates_release_request_for_pending_developer_release_version
    app = OpenStruct.new(id: "app-123")
    client = FakeClient.new(
      app: app,
      versions: [
        FakeVersion.new(id: "version-123", version_string: "1.2.0", app_store_state: "PENDING_DEVELOPER_RELEASE"),
        FakeVersion.new(id: "version-123", version_string: "1.2.0", app_store_state: "PROCESSING_FOR_APP_STORE")
      ]
    )
    review = build_review(client)

    stdout, = capture_io do
      review.send(:release_to_store)
    end

    assert_equal 2, client.find_version_calls.length
    assert_equal ASCTooling::Review::RELEASEABLE_STATES, client.find_version_calls.first[:states]
    assert_nil client.find_version_calls.first[:app_version]
    assert_equal "1.2.0", client.find_version_calls.last[:app_version]

    assert_equal 1, client.requests.length
    assert_equal "POST", client.requests.first[:method]
    assert_equal "/v1/appStoreVersionReleaseRequests", client.requests.first[:path]
    assert_nil client.requests.first[:params]
    assert_equal(
      {
        data: {
          type: "appStoreVersionReleaseRequests",
          relationships: {
            appStoreVersion: {
              data: {
                type: "appStoreVersions",
                id: "version-123"
              }
            }
          }
        }
      },
      client.requests.first[:body]
    )

    assert_includes stdout, "Release request release-request-123 created for 1.2.0"
    assert_includes stdout, "Version 1.2.0 is now PROCESSING_FOR_APP_STORE"
  end

  def test_release_is_noop_when_version_is_already_processing
    app = OpenStruct.new(id: "app-123")
    client = FakeClient.new(
      app: app,
      versions: [
        FakeVersion.new(id: "version-123", version_string: "1.2.0", app_store_state: "PROCESSING_FOR_APP_STORE")
      ]
    )
    review = build_review(client)

    stdout, = capture_io do
      review.send(:release_to_store)
    end

    assert_equal 1, client.find_version_calls.length
    assert_equal 0, client.requests.length
    assert_includes stdout, "Version 1.2.0 is PROCESSING_FOR_APP_STORE; nothing to release"
  end

  def test_withdraw_removes_in_review_version_from_review
    app = OpenStruct.new(id: "app-123")
    client = FakeClient.new(
      app: app,
      versions: [
        FakeVersion.new(id: "version-123", version_string: "1.2.0", app_store_state: "IN_REVIEW"),
        FakeVersion.new(id: "version-123", version_string: "1.2.0", app_store_state: "DEVELOPER_REJECTED")
      ]
    )
    review = build_review(client, app_version: "1.2.0")

    stdout, = capture_io do
      review.send(:withdraw_from_review)
    end

    assert_equal 2, client.find_version_calls.length
    assert_nil client.find_version_calls.first[:states]
    assert_equal "1.2.0", client.find_version_calls.first[:app_version]
    assert_nil client.find_version_calls.last[:states]
    assert_equal "1.2.0", client.find_version_calls.last[:app_version]

    assert_equal 1, client.requests.length
    assert_equal "GET", client.requests.first[:method]
    assert_equal "/v1/appStoreVersions/version-123/appStoreVersionSubmission", client.requests.first[:path]
    assert_equal ["/v1/appStoreVersionSubmissions/release-request-123"], client.deleted_resources
    assert_includes stdout, "Withdrew 1.2.0; version state is now DEVELOPER_REJECTED"
  end

  def test_withdraw_supports_dry_run_for_in_review_version
    app = OpenStruct.new(id: "app-123")
    client = FakeClient.new(
      app: app,
      versions: [
        FakeVersion.new(id: "version-123", version_string: "1.2.0", app_store_state: "IN_REVIEW")
      ]
    )
    review = build_review(client, app_version: "1.2.0", dry_run: true)

    stdout, = capture_io do
      review.send(:withdraw_from_review)
    end

    assert_equal 1, client.find_version_calls.length
    assert_equal 1, client.requests.length
    assert_empty client.deleted_resources
    assert_includes stdout, "Dry run: would withdraw version 1.2.0 from review."
  end

  def test_withdraw_is_noop_for_non_withdrawable_version
    app = OpenStruct.new(id: "app-123")
    client = FakeClient.new(
      app: app,
      versions: [
        FakeVersion.new(id: "version-123", version_string: "1.2.0", app_store_state: "READY_FOR_SALE")
      ]
    )
    review = build_review(client, app_version: "1.2.0")

    stdout, = capture_io do
      review.send(:withdraw_from_review)
    end

    assert_equal 1, client.find_version_calls.length
    assert_empty client.requests
    assert_empty client.deleted_resources
    assert_includes stdout, "Version 1.2.0 is READY_FOR_SALE; nothing to withdraw"
  end

  private

  def build_review(client, options = {})
    review = ASCTooling::Review.allocate
    review.instance_variable_set(
      :@options,
      {
        bundle_id: "com.example.app",
        platform: "macos"
      }.merge(options)
    )
    review.instance_variable_set(:@asc, client)
    review
  end
end
