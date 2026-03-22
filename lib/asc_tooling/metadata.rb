module ASCTooling
  # Port the reusable logic from NightOwl/scripts/asc_metadata.rb into this class.
  #
  # Expected responsibilities:
  # - read current metadata
  # - apply app info localization changes
  # - apply version localization changes
  class Metadata
    def self.run(_argv = ARGV)
      raise NotImplementedError, "Port metadata workflow from NightOwl/scripts/asc_metadata.rb"
    end
  end
end
