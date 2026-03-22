module ASCTooling
  # Port the reusable logic from NightOwl/scripts/asc_review.rb into this class.
  #
  # Expected responsibilities:
  # - status
  # - submit
  # - withdraw
  class Review
    def self.run(_argv = ARGV)
      raise NotImplementedError, "Port review workflow from NightOwl/scripts/asc_review.rb"
    end
  end
end
