module NexusCli
  class Connection
    attr_reader :nexus
    attr_reader :configuration

    def initialize(configuration)
      @configuration = configuration
      @nexus = setup_nexus(configuration)
    end

    # Returns an HTTPClient instance with settings to connect
    # to a Nexus server.
    #
    # @return [HTTPClient]
    def setup_nexus(configuration)
      client = HTTPClient.new
      client.send_timeout = 6000
      client.receive_timeout = 6000
      # https://github.com/nahi/httpclient/issues/63
      client.set_auth(nil, configuration['username'], configuration['password'])
      client.www_auth.basic_auth.challenge(configuration['url'])
      client.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_NONE unless @ssl_verify
      
      client
    end

    # Joins a given url to the current url stored in the configuraiton
    # and returns the combined String.
    #
    # @param [String] url
    #
    # @return [String]
    def nexus_url(url)
      File.join(configuration['url'], url)
    end

    # Gets that current status of the Nexus server. On a non-error
    # status code, returns a Hash of values from the server.
    #
    # @return [Hash]
    def status
      response = nexus.get(nexus_url("service/local/status"))
      case response.status
      when 200
        doc = Nokogiri::XML(response.content).xpath("/status/data")
        data = Hash.new
        data['app_name'] = doc.xpath("appName")[0].text
        data['version'] = doc.xpath("version")[0].text
        data['edition_long'] = doc.xpath("editionLong")[0].text
        data['state'] = doc.xpath("state")[0].text
        data['started_at'] = doc.xpath("startedAt")[0].text
        data['base_url'] = doc.xpath("baseUrl")[0].text
        return data
      when 401
        raise PermissionsException
      when 503
        raise CouldNotConnectToNexusException
      else
        raise UnexpectedStatusCodeException.new(response.status)
      end
    end

    # Transforms a given [String] into a sanitized version by
    # replacing spaces with underscores and downcasing.
    # 
    # @param  unsanitized_string [String] the String to sanitize
    # 
    # @return [String] the sanitized String
    def sanitize_for_id(unsanitized_string)
      unsanitized_string.gsub(" ", "_").downcase
    end

    # Parses a given artifact string into its
    # four, distinct, Maven pieces.
    # 
    # @param  artifact [String] the Maven identifier
    # 
    # @return [Array<String>] an Array with four elements
    def parse_artifact_string(artifact)
      split_artifact = artifact.split(":")
      if(split_artifact.size < 4)
        raise ArtifactMalformedException
      end
      group_id, artifact_id, version, extension = split_artifact
      version.upcase! if version.casecmp("latest")
      return group_id, artifact_id, version, extension
    end

    # Determines whether or not the Nexus server being
    # connected to is running Nexus Pro.
    def running_nexus_pro?
      status['edition_long'] == "Professional"
    end
  end
end