module ASCTooling
  module Pagination
    def paginated_resources(path, params: {}, limit: Client::DEFAULT_PAGE_LIMIT)
      paginated_document(path, params: params, limit: limit).fetch("data")
    end

    def paginated_document(path, params: {}, limit: Client::DEFAULT_PAGE_LIMIT)
      document = { "data" => [], "included" => [] }

      each_paginated_response(path, params: params, limit: limit) do |response|
        document["data"].concat(response.fetch("data", []))
        document["included"].concat(response.fetch("included", []))
      end

      document["included"].uniq! { |resource| [resource["type"], resource["id"]] }
      document
    end

    private

    def each_paginated_response(path, params:, limit:)
      next_path = path
      next_params = params.merge("limit" => limit.to_s)

      loop do
        response = request_json("GET", next_path, params: next_params)
        yield response

        next_link = response.dig("links", "next")
        break if Client.blank?(next_link)

        uri = URI(next_link)
        next_path = uri.path
        next_params = URI.decode_www_form(uri.query || "").to_h
      end
    end
  end
end
