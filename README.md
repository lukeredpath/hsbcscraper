# HSBC Business Banking Scraper

A simple scraping mechanism, built on top of Mechanize, with a scraper for the HSBC Business banking website.

All of the dependencies are managed by Bundler. Run `bundle install` to get up and running.

The scraper architecture is quite simple, and is inspired by the Rack middleware API.

The `Scraper` class handles the pipeline - use the `build` method to build a pipeline of different scrapers. See `hsbc.rb` for an example.

Scraper modules for logging in and out and downloading statements from HSBC business banking are provided.

These scripts obviously contain no credentials - it is recommended you store these in something like the OSX keychain, which is supported natively in the provided scripts. Here's an example:

```ruby
download_handler = ->(downloaded_file) {
  downloaded_file.save('/Users/luke/Desktop/statement.qif')
}

# username, password and bank account number are stored in the OSX keychain
keychain_item = Keychain.generic_passwords.where(:service => 'hsbc-business').first

raise "Couldn't find keychain item!" unless keychain_item

statement_date_range = [HSBC.last_statement_date, Date.today]

scraper = Scraper.build(HSBC::BANKING_URL) do
  use HSBC::Login.new(keychain_item.account, keychain_item.password, HSBC::InteractiveShellKeyfob.new)
  use HSBC::DownloadStatement.new(keychain_item.comment, statement_date_range, &download_handler)
  use HSBC::Logout
end

scraper.run
```

The `HSBC::DownloadStatement` scraper takes a block to handle the downloaded statement (which is an instance of Mechanize::File). 

The above snippet will try to find the HSBC credentials from your OSX keychain with the service name of 'hsbc-business'. It will exit if it doesn't find them. See the `HSBC::Login` class for more details on how these credentials are used.

It will then read the date of the last downloaded statement from `~/.hsbc` and use that to fetch a statement from that date until the current date.

You will not be able to run these scripts using some automated method like cron - you will need to be present to run the scripts as it will prompt you from a code from your security fob.

## Importing statement into FreeAgent

If you also happen to be using [FreeAgent](http://freeagent.com) to manage your books, you can automatically import your statement into FreeAgent using their API.

The `FreeAgent::Authenticator` class takes care of OAuth2 authentication. It expects a "credentials" object that responds to `account` and `password`. A method, `FreeAgent.credentials_from_keychain` is provided that can retrieve these credentials from the OSX keychain.

See `upload_statement_to_freeagent.rb` for more details. You will need to modify the `HSBC_BANK_ACCOUNT_ID` constant to match the ID of your HSBC account in FreeAgent.
