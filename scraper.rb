require 'mechanize'

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
    
    if ENV['DEBUG']
      agent.log = Logger.new(STDOUT)
    end
    
    @flows.each do |flow|
      flow.run(agent)
    end
  end
end
