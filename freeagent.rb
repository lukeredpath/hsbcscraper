gem 'ruby-keychain'

require 'keychain'
require 'oauth2'

module FreeAgent
  def self.credentials_from_keychain
    credentials = Keychain.generic_passwords.where(:service => 'com.freeagent.api.CLI').first

    if credentials.nil?
      # TODO: support oauth registration 
      puts "Could not find credentials for API."
      exit 1
    end
    
    credentials
  end
  
  class Authenticator
    attr_reader :client
    
    def initialize(oauth_credentials, connection_opts = {})
      @credentials = oauth_credentials
      @client = OAuth2::Client.new(@credentials.account, @credentials.password, {
        :site          => 'https://api.freeagent.com',
        :authorize_url => '/v2/approve_app',
        :token_url     => '/v2/token_endpoint',
        :connection_opts => connection_opts
      })
    end
    
    def obtain_access_token
      token_credentials_service = @credentials.label + ".token"
      refresh_token_credentials = Keychain.generic_passwords.where(:service => token_credentials_service).first
      
      if refresh_token_credentials
        # just create a new token from the refresh token
        token = OAuth2::AccessToken.new(@client, nil, refresh_token: refresh_token_credentials.password)
        token.refresh!
      else
        # we need to start the whole oauth flow to obtain an access to token
        puts "Opening authorization page in Safari..."
        system "open -a Safari '#{@client.auth_code.authorize_url.strip}'"
        
        print "Enter the value of code: "
        token_code = STDIN.gets.strip

        # store the refresh token so we can access it next time
        @client.auth_code.get_token(token_code).tap do |access_token|
          Keychain.generic_passwords.create(
            :service => token_credentials_service, 
            :password => access_token.refresh_token
          )
        end        
      end
    end
  end
end
