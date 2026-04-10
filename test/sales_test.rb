require "minitest/autorun"
require "ostruct"
require "stringio"
require "tmpdir"
require "zlib"

require "asc_tooling/sales"

class ASCToolingSalesTest < Minitest::Test
  class FakeClient
    attr_reader :requests

    def initialize(app:, report_blob:)
      @app = app
      @report_blob = report_blob
      @requests = []
    end

    def find_app!(_bundle_id)
      @app
    end

    def request_blob(method, path, params: nil, body: nil, accept: "application/a-gzip")
      @requests << {
        method: method,
        path: path,
        params: params,
        body: body,
        accept: accept
      }
      @report_blob
    end
  end

  def test_report_params_include_vendor_number_defaults_and_optional_date
    sales = build_sales(nil, vendor_number: "12345678", report_date: "2026-04-10")

    assert_equal(
      {
        "filter[vendorNumber]" => "12345678",
        "filter[reportType]" => "SALES",
        "filter[reportSubType]" => "SUMMARY",
        "filter[frequency]" => "DAILY",
        "filter[version]" => "1_1",
        "filter[reportDate]" => "2026-04-10"
      },
      sales.send(:report_params)
    )
  end

  def test_summarize_units_groups_downloads_redownloads_updates_and_other
    app = OpenStruct.new(id: "6760773101", name: "Rouse: Stay Awake", bundle_id: "com.example.rouse")
    client = FakeClient.new(app: app, report_blob: summary_report_blob)
    sales = build_sales(client, bundle_id: app.bundle_id, vendor_number: "12345678")

    summary = sales.send(:summarize_units, app)

    assert_equal 3, summary[:matching_rows]
    assert_equal 5.0, summary[:downloads_units]
    assert_equal 2.0, summary[:redownload_units]
    assert_equal 4.0, summary[:updates_units]
    assert_equal 0.0, summary[:other_units]
    assert_equal 11.0, summary[:total_units]
    assert_equal({ "JP" => 2.0, "US" => 9.0 }, summary[:by_country])

    assert_equal 1, client.requests.length
    assert_equal "GET", client.requests.first[:method]
    assert_equal "/v1/salesReports", client.requests.first[:path]
  end

  def test_print_report_decompresses_gzip_and_writes_output
    app = OpenStruct.new(id: "6760773101", name: "Rouse: Stay Awake", bundle_id: "com.example.rouse")
    client = FakeClient.new(app: app, report_blob: gzip(summary_report_text))

    Dir.mktmpdir do |dir|
      output_path = File.join(dir, "sales.tsv")
      sales = build_sales(client, vendor_number: "12345678", output: output_path)

      stdout, = capture_io do
        sales.send(:print_report)
      end

      assert_includes stdout, "Saved report to #{output_path}"
      assert_equal summary_report_text, File.read(output_path)
    end
  end

  private

  def build_sales(client, options = {})
    sales = ASCTooling::Sales.allocate
    sales.instance_variable_set(
      :@options,
      {
        command: "units",
        bundle_id: "com.example.rouse",
        report_type: "SALES",
        report_subtype: "SUMMARY",
        frequency: "DAILY",
        report_version: "1_1",
        platform: "macos"
      }.merge(options)
    )
    sales.instance_variable_set(:@asc, client)
    sales
  end

  def summary_report_blob
    gzip(summary_report_text)
  end

  def summary_report_text
    <<~TSV
      Provider\tProvider Country\tSKU\tDeveloper\tTitle\tVersion\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tBegin Date\tEnd Date\tCustomer Currency\tCountry Code\tCurrency of Proceeds\tApple Identifier\tCustomer Price\tPromo Code\tParent Identifier\tSubscription\tPeriod\tCategory\tCMB\tSupported Platforms\tDevice\tPreserved Pricing\tProceeds Reason\tClient\tOrder Type
      APPLE\tUS\trouse\tJamin Zhou\tRouse: Stay Awake\t1.2.0\tF1\t5\t0\t04/10/2026\t04/10/2026\tUSD\tUS\tUSD\t6760773101\t0\t\t\t\t\tUtilities\t\tmacOS\tDesktop\t\t\t\t
      APPLE\tUS\trouse\tJamin Zhou\tRouse: Stay Awake\t1.2.0\t3F\t2\t0\t04/10/2026\t04/10/2026\tJPY\tJP\tJPY\t6760773101\t0\t\t\t\t\tUtilities\t\tmacOS\tDesktop\t\t\t\t
      APPLE\tUS\trouse\tJamin Zhou\tRouse: Stay Awake\t1.2.0\tF7\t4\t0\t04/10/2026\t04/10/2026\tUSD\tUS\tUSD\t6760773101\t0\t\t\t\t\tUtilities\t\tmacOS\tDesktop\t\t\t\t
      APPLE\tUS\tother\tSomeone Else\tOther App\t1.0.0\tF1\t99\t0\t04/10/2026\t04/10/2026\tUSD\tUS\tUSD\t1234567890\t0\t\t\t\t\tUtilities\t\tmacOS\tDesktop\t\t\t\t
    TSV
  end

  def gzip(text)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) { |writer| writer.write(text) }
    io.string
  end
end
