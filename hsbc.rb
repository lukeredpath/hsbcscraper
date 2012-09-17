require 'rubygems'
require 'mechanize'
require 'keychain'

class Scraper
  def initialize(url)
    @url = url
    @flows = []
  end
  
  def self.build(url, &block)
    scraper = new(url)
    scraper.instance_eval(&block)
    scraper
  end
  
  def use(flow)
    @flows << flow
  end
  
  def run
    agent = Mechanize.new
    agent.get(@url)
    
    @flows.each do |flow|
      flow.run(agent)
    end
  end
end

module HSBC
  class Login
    def initialize(username, password, keyfob)
      @username = username
      @password = password
      @keyfob = keyfob
    end
    
    def run(agent)
      begin_login(agent.current_page)
      submit_username(agent.current_page)
      submit_credentials(agent.current_page)
      select_company_from_list(agent.current_page)
    end
    
    private
    
    def begin_login(page)
      page.link_with(text: /LOG ON/i).click
    end
    
    def submit_username(page)
      find_input_form(page) do |form|
        form.set_fields(
          userid: @username
        )
        form.submit
      end
    end
    
    def submit_credentials(page)
      find_input_form(page) do |form|
        form.set_fields(
          memorableAnswer: @password,
          idv_OtpCredential: @keyfob.generate_code
        )
        form.submit
      end
    end
    
    def select_company_from_list(page)
      page.link_with(href: /account-list/).click
    end
    
    def find_input_form(page, &block)
      page.form_with(name: /PC_.*_inputForm/, &block)
    end
  end
  
  class Logout
    def self.run(agent)
      agent.current_page.link_with(text: /LOG OFF/i).click
    end
  end
  
  class DownloadStatement
    def initialize(account_number, download_handler, date_range = nil)
      @account_number = account_number
      @date_range = date_range
      @download_handler = download_handler
    end
    
    def run(agent)
      select_account(agent.current_page)
      view_recent_transactions(agent.current_page)
      adjust_date_range(agent.current_page) if @date_range
      download_qif_statement(agent)
    end
    
    private
    
    def select_account(page)
      page.link_with(text: /#{@account_number}/).click
    end
    
    def view_recent_transactions(page)
      page.link_with(text: /View Recent Transactions/).click
    end
    
    def adjust_date_range(page)
      page.form_with(name: /further_display/) do |form|
        form.set_fields(
          'historicDate.day'   => @date_range[0].day,
          'historicDate.month' => @date_range[0].month,
          'historicDate.year'  => @date_range[0].year,
          'recentDate.day'     => @date_range[1].day,
          'recentDate.month'   => @date_range[1].month,
          'recentDate.year'    => @date_range[1].year
        )
        form.submit
      end
    end
    
    def download_qif_statement(agent)
      agent.current_page.form_with(name: /statement/) do |form|
        form.fileFormat = 'QIF'
        file = form.submit
        @download_handler.handle_downloaded_file(file)
        agent.back
      end
    end
  end
  
  class InteractiveShellKeyfob
    def initialize(output = STDOUT)
      @output = output
    end
    
    def generate_code
      @output.print "Enter the code from your security device: "
      gets.strip
    end
  end
end

class StatementSaver
  def initialize(path)
    @path = path
  end
  
  def handle_downloaded_file(file)
    file.save(@path)
  end
end

BANKING_URL = "https://www.business.hsbc.co.uk/1/2/home"

# a 'delegate' object used by the DownloadStatement flow, saves it to disk
statement_saver = StatementSaver.new('/Users/luke/Desktop/statement.qif')

# username, password and bank account number are stored in the OSX keychain
keychain_item = Keychain.items.find { |item| item.label == 'hsbc-business' }

scraper = Scraper.build(BANKING_URL) do
  use HSBC::Login.new(keychain_item.account, keychain_item.password, HSBC::InteractiveShellKeyfob.new)
  use HSBC::DownloadStatement.new(keychain_item.comment, statement_saver)
  use HSBC::Logout
end

scraper.run
