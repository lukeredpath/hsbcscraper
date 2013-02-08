$LOAD_PATH.unshift(".")

require 'bundler/setup'
require 'hsbc'
require 'freeagent'
require 'tempfile'
require 'typhoeus'
require 'yaml'
require 'qif'

HSBC_BANK_ACCOUNT_ID = 7213

# username, password and bank account number are stored in the OSX keychain
keychain_item = Keychain.generic_passwords.where(:service => 'hsbc-business').first

if keychain_item.nil?
  puts "Couldn't find keychain item for HSBC Business Banking."
  exit 1
end

class MechanizeFileIOAdapter
  def initialize(file)
    @file = file
    @read = false
  end
  
  def read(*ignored)
    unless @read
      @read = true
      @file.body
    end
  end
  
  def rewind
    @read = false
  end
  
  def length
    @file.body.length
  end
end

statement_date_range = [HSBC.last_statement_date, Date.today]

statement_handler = proc do |downloaded_statement|
  authenticator = FreeAgent::Authenticator.new(FreeAgent.credentials_from_keychain('com.freeagent.api.CLI'))

  # we will need multipart upload support for statements
  authenticator.client.connection.build do |faraday|
    faraday.request :multipart
    faraday.request :url_encoded
    faraday.adapter Faraday.default_adapter
  end

  authenticator.obtain_access_token.tap do |token|
    puts "Posting statement..."
    
    file_to_upload = MechanizeFileIOAdapter.new(downloaded_statement)

    response = token.post("/v2/bank_transactions/statement?bank_account=#{HSBC_BANK_ACCOUNT_ID}", {
      :body => {:statement => Faraday::UploadIO.new(file_to_upload, 'text/qif')}
    })
    
    file_to_upload.rewind
    qif = Qif::Reader.new(file_to_upload.read)

    if response.status == 200
      HSBC.update_last_statement_date
      puts "Statement uploaded successfully."
      puts "#{qif.size} transactions imported."
    else
      puts "Statement upload failed! (#{response.status}: #{response.body})."
      exit 1
    end
  end
end

scraper = Scraper.build(HSBC::BANKING_URL) do
  use HSBC::Login.new(keychain_item.account, keychain_item.password, HSBC::InteractiveShellKeyfob.new)
  use HSBC::DownloadStatement.new(keychain_item.comment, statement_date_range, &statement_handler)
  use HSBC::Logout
end

scraper.run
