module ASCTooling
  # Port the reusable logic from NightOwl/scripts/upload_app_store_screenshots.rb into this class.
  #
  # Expected responsibilities:
  # - screenshot set lookup
  # - upload / replace / status
  class Screenshots
    def self.run(_argv = ARGV)
      raise NotImplementedError, "Port screenshot workflow from NightOwl/scripts/upload_app_store_screenshots.rb"
    end
  end
end
