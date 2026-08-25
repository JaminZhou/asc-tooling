require_relative "test_helper"

class ASCToolingReviewTest < Minitest::Test
  FakeBuild = Struct.new(:id, :version, :processing_state, keyword_init: true)
  FakeVersion = Struct.new(:id, :version_string, :app_store_state, :build, :release_type, keyword_init: true)

  class FakeClient
    attr_reader :deleted_resources, :find_version_calls, :requests

    def initialize(app:, versions:, builds: [])
      @app = app
      @versions = versions.dup
      @builds = builds
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

    def find_editable_version!(app, platform:, app_version: nil)
      find_version!(app, platform: platform, app_version: app_version, states: ASCTooling::Client::EDITABLE_STATES)
    end

    def build_candidates(_app_id, _app_version, limit:)
      raise "unexpected build limit #{limit}" unless limit == ASCTooling::Review::BUILD_LIMIT

      @builds
    end

    def find_build_by_number(_app_id, _app_version, build_number)
      @builds.find { |build| build.dig("attributes", "version") == build_number }
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

  def test_attach_build_links_selected_valid_build_and_verifies_read_back
    app = OpenStruct.new(id: "app-123")
    selected_build = {
      "id" => "build-123",
      "attributes" => {
        "version" => "2026082501",
        "processingState" => "VALID",
        "buildAudienceType" => "APP_STORE_ELIGIBLE"
      }
    }
    client = FakeClient.new(
      app: app,
      versions: [
        FakeVersion.new(id: "version-123", version_string: "1.3.0", app_store_state: "PREPARE_FOR_SUBMISSION"),
        FakeVersion.new(
          id: "version-123",
          version_string: "1.3.0",
          app_store_state: "PREPARE_FOR_SUBMISSION",
          build: FakeBuild.new(id: "build-123", version: "2026082501", processing_state: "VALID")
        )
      ],
      builds: [selected_build]
    )
    review = build_review(client, app_version: "1.3.0", build_number: "2026082501")

    stdout, = capture_io do
      review.send(:attach_build)
    end

    assert_equal 2, client.find_version_calls.length
    assert_equal 1, client.requests.length
    assert_equal "PATCH", client.requests.first[:method]
    assert_equal "/v1/appStoreVersions/version-123/relationships/build", client.requests.first[:path]
    assert_equal(
      { data: { type: "builds", id: "build-123" } },
      client.requests.first[:body]
    )
    assert_includes stdout, "Attached build 2026082501 to version 1.3.0"
  end

  def test_attach_build_dry_run_does_not_mutate
    app = OpenStruct.new(id: "app-123")
    build = {
      "id" => "build-123",
      "attributes" => {
        "version" => "2026082501",
        "processingState" => "VALID",
        "buildAudienceType" => "APP_STORE_ELIGIBLE"
      }
    }
    client = FakeClient.new(
      app: app,
      versions: [FakeVersion.new(id: "version-123", version_string: "1.3.0", app_store_state: "PREPARE_FOR_SUBMISSION")],
      builds: [build]
    )
    review = build_review(client, app_version: "1.3.0", build_number: "2026082501", dry_run: true)

    stdout, = capture_io do
      review.send(:attach_build)
    end

    assert_empty client.requests
    assert_includes stdout, "Dry run: would attach build 2026082501 to version 1.3.0."
  end

  def test_find_target_build_rejects_selected_ineligible_build
    app = OpenStruct.new(id: "app-123")
    build = {
      "id" => "build-123",
      "attributes" => {
        "version" => "2026082501",
        "processingState" => "PROCESSING",
        "buildAudienceType" => "APP_STORE_ELIGIBLE"
      }
    }
    client = FakeClient.new(app: app, versions: [], builds: [build])
    review = build_review(client, app_version: "1.3.0", build_number: "2026082501")

    error = assert_raises(OptionParser::InvalidArgument) do
      review.send(:find_target_build!, app.id, "1.3.0")
    end

    assert_includes error.message, "not VALID and APP_STORE_ELIGIBLE"
  end

  def test_review_submission_items_reports_app_and_iap_version_linkages
    client = FakeClient.new(app: OpenStruct.new(id: "app-123"), versions: [])
    client.define_singleton_method(:request_json) do |method, path, params: nil, body: nil|
      @requests << { method: method, path: path, params: params, body: body }
      {
        "data" => [
          {
            "type" => "reviewSubmissionItems",
            "id" => "item-app",
            "attributes" => { "state" => "READY_FOR_REVIEW" },
            "relationships" => {
              "appStoreVersion" => { "data" => { "type" => "appStoreVersions", "id" => "version-123" } }
            }
          },
          {
            "type" => "reviewSubmissionItems",
            "id" => "item-iap",
            "attributes" => { "state" => "READY_FOR_REVIEW" },
            "relationships" => {
              "inAppPurchaseVersion" => { "data" => { "type" => "inAppPurchaseVersions", "id" => "iap-version-123" } }
            }
          }
        ],
        "included" => [
          {
            "type" => "appStoreVersions",
            "id" => "version-123",
            "attributes" => { "versionString" => "1.3.0" }
          },
          {
            "type" => "inAppPurchaseVersions",
            "id" => "iap-version-123",
            "attributes" => { "version" => 1, "state" => "READY_FOR_REVIEW" }
          }
        ]
      }
    end
    review = build_review(client)

    items = review.send(:review_submission_items, "submission-123")

    assert_equal 2, items.length
    assert_equal "appStoreVersion", items.first[:relationship]
    assert_equal "1.3.0", items.first[:version]
    assert_equal "inAppPurchaseVersion", items.last[:relationship]
    assert_equal 1, items.last[:version]
    assert_equal(
      "inAppPurchaseVersion iap-version-123 (version 1) [READY_FOR_REVIEW]",
      review.send(:review_submission_item_label, items.last)
    )
    assert_equal(
      "appStoreVersion,inAppPurchaseVersion",
      client.requests.first[:params]["include"]
    )
  end

  def test_attach_build_requires_explicit_app_version
    _, stderr = capture_io do
      result = ASCTooling::Review.run(["attach-build", "--bundle-id", "com.example.app"])
      assert_equal 1, result
    end

    assert_includes stderr, "--app-version is required for attach-build"
  end

  def test_submit_attaches_selected_build_and_immediately_submits_draft
    app = OpenStruct.new(id: "app-123")
    selected_build = {
      "id" => "build-123",
      "attributes" => {
        "version" => "2026082501",
        "processingState" => "VALID",
        "buildAudienceType" => "APP_STORE_ELIGIBLE"
      }
    }
    client = FakeClient.new(
      app: app,
      versions: [
        FakeVersion.new(
          id: "version-123",
          version_string: "1.3.0",
          app_store_state: "PREPARE_FOR_SUBMISSION",
          release_type: "MANUAL"
        ),
        FakeVersion.new(
          id: "version-123",
          version_string: "1.3.0",
          app_store_state: "PREPARE_FOR_SUBMISSION",
          release_type: "MANUAL",
          build: FakeBuild.new(id: "build-123", version: "2026082501", processing_state: "VALID")
        )
      ],
      builds: [selected_build]
    )
    configure_submit_requests(client)
    review = build_review(
      client,
      app_version: "1.3.0",
      build_number: "2026082501"
    )

    stdout, = capture_io do
      review.send(:submit_for_review)
    end

    assert_equal(
      [
        ["GET", "/v1/reviewSubmissions"],
        ["PATCH", "/v1/appStoreVersions/version-123/relationships/build"],
        ["GET", "/v1/reviewSubmissions"],
        ["GET", "/v1/reviewSubmissions/submission-123/items"],
        ["POST", "/v1/reviewSubmissionItems"],
        ["PATCH", "/v1/reviewSubmissions/submission-123"]
      ],
      client.requests.map { |request| [request[:method], request[:path]] }
    )
    assert_includes stdout, "Submitted 1.3.0 (2026082501)"
    assert_includes stdout, "Review submission submission-123 is now WAITING_FOR_REVIEW"
  end

  private

  def configure_submit_requests(client)
    client.define_singleton_method(:request_json) do |method, path, params: nil, body: nil|
      @requests << { method: method, path: path, params: params, body: body }
      case [method, path]
      when ["GET", "/v1/reviewSubmissions"]
        {
          "data" => [
            {
              "id" => "submission-123",
              "attributes" => { "state" => "READY_FOR_REVIEW" }
            }
          ]
        }
      when ["GET", "/v1/reviewSubmissions/submission-123/items"]
        { "data" => [], "included" => [] }
      when ["POST", "/v1/reviewSubmissionItems"]
        { "data" => { "id" => "item-123" } }
      when ["PATCH", "/v1/reviewSubmissions/submission-123"]
        {
          "data" => {
            "id" => "submission-123",
            "attributes" => { "state" => "WAITING_FOR_REVIEW" }
          }
        }
      when ["PATCH", "/v1/appStoreVersions/version-123/relationships/build"]
        { "data" => { "type" => "builds", "id" => "build-123" } }
      else
        raise "unexpected request: #{method} #{path}"
      end
    end
  end

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
