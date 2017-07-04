require 'bundler/setup'
require 'trello'
require 'date'
require 'yaml'
require 'rufus-scheduler'
require 'mail'

def load_config
  if File.exist? File.expand_path("config.yml")
    YAML.load_file(File.expand_path("config.yml"))
  else
    raise "ERROR: Config file not found!"
  end
end

def authenticate(api_key, app_token)
  Trello.configure do |config|
    config.developer_public_key = api_key
    config.member_token = app_token
  end
end

def make_report(board_id, list_name, period, ex_labels=nil)
  board = Trello::Board.find board_id
  cards = board.lists.detect{|l| l.name == list_name}.cards

  period_start = DateTime.now - period

  cards = cards.select{|c| c.last_activity_date >= period_start}

  if ex_labels
    cards = cards.select{|c| (c.labels.map{|lbl| lbl.name} & ex_labels).empty? }
  end

  report = "#{list_name}:\n"

  cards.each do |c|
    if c.comments.length > 0
      report += "\t- #{c.comments[0].text}\n"
    else
      report += "\t- #{c.desc}\n" unless c.desc.empty?
    end
  end

  report += "\n"
end

def send_report(txt, mail_config)
  mail = Mail.new do
    to        mail_config[:to]
    from      mail_config[:from]
    subject   eval('"' + mail_config[:subject] + '"')
    body      txt
  end

  mail.delivery_method :sendmail
  mail.deliver!
end

# Load the YAML config
config = load_config

# Configure auth in the trello library
authenticate config[:trello][:api_key], config[:trello][:app_token]

#Create our scheduler
scheduler = Rufus::Scheduler.new

# For each report we need
config[:reports].each do |r|
  scheduler.cron r[:cron] do
    report_txt = ""

    r[:lists].each do |list|
      report_txt += make_report r[:board], list, r[:period], r[:exclude_labels]
    end

    ret = send_report report_txt, config[:email]

    if ret
      puts "Report has been sent."
      puts "-"*50
      puts ret
      puts "\n\n"
    end
  end
end

scheduler.join
