require "curb"
require "cgi"
require "nokogiri"
require "timers"

class CaltrainRealtime
  BaseURL = "http://www.caltrain.com/"
  Retries = 3

  def self.get_departures(stations)
    t = []
    t << Time.now
    m = Curl::Multi.new

    departures = {}
    stations.each do |name|
      m.add(Curl::Easy.new(BaseURL) do |curl|
        fields = {
          "__EVENTTARGET" => "",
          "__CALLBACKID" => "ctl09",
          "__CALLBACKPARAM" => "refreshStation=#{name}"
        }
        curl.post_body = fields.map{|f,k| "#{CGI.escape(f)}=#{CGI.escape(k)}"}.join('&')
        curl.on_success do |c|
          departures[name] = c.body
        end
        curl.timeout = 10
      end)
    end

    m.perform
    t << Time.now

    departures.keys.each do |name|
      if error_response?(departures[name])
        puts "got an error for #{name}, making special request"
        departures[name] = make_departure_request(name)
      end
    end
    t << Time.now

    puts "scrape times: " + t.join(" -- ")

    departures
  end

  def self.get_departure(name)
    body = make_departure_request(name)
    process_departure(body)
  end

  def self.get_start_of_minute()
    # make requests 5 seconds apart until the minute changes
    time = nil

    t = Timers::Group.new
    t.every(5) do
      body = make_departure_request("San Francisco")
      new_time = extract_time(body)
      if new_time != time && time != nil
        return Time.now
      end
      time = new_time
    end

    loop { t.wait }
  end

  def self.get_stations()
    body = Curl.get(BaseURL).body

    process_station_names(body)
  end

  def self.make_departure_request(name)
    retries = Retries
    begin
      # XXX no timeout here, but hoping that's ok
      body = Curl.post(BaseURL, {"__EVENTTARGET" => "", "__CALLBACKID" => "ctl09", "__CALLBACKPARAM" => "refreshStation=#{name}"}).body
      retries -= 1
    end while error_response?(body) && retries > 0

    if retries < Retries - 1
      puts "had to retry #{Retries - retries - 1} times for #{name}"
    end

    # note that we can still return an error response here
    body
  end


  def self.process_departure(body)
    time = extract_time(body)
    xml = Nokogiri.HTML(body)
    xml.xpath("//table/tr[@class='ipf-st-ip-trains-subtable-tr']").map do |t|
      arr = t.children.map &:text
      arr << time
    end
  end

  def self.process_station_names(body)
    xml = Nokogiri.HTML(body)
    xml.xpath("//*[@id='ipf-st-ip-station']/option").map do |s|
      s["value"]
    end.reject do |n|
      n =~ /\(/
    end
  end

  def self.extract_time(body)
    /<IRONPOINT>TIME<\/IRONPOINT>as of&nbsp;(?<time>[^<]+)<IRONPOINT>TIME<\/IRONPOINT>/.match(body)[:time]
  end

  def self.error_response?(body)
    body.include?("An error occurred contacting the web service")
  end
end
