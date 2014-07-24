require "curb"
require "cgi"
require "nokogiri"

class CaltrainRealtime
  BaseURL = "http://www.caltrain.com/"

  def self.get_departures(stations)
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
          departures[name] = process_departure(c.body)
        end
      end)
    end

    m.perform
    departures
  end

  def self.get_departure(name)
    body = Curl.post(BaseURL, {"__EVENTTARGET" => "", "__CALLBACKID" => "ctl09", "__CALLBACKPARAM" => "refreshStation=#{name}"}).body

    process_departure(body)
  end

  def self.get_stations()
    body = Curl.get(BaseURL).body

    process_station_names(body)
  end

  private

  def self.process_departure(body)
    time = /<IRONPOINT>TIME<\/IRONPOINT>as of&nbsp;(?<time>[^<]+)<IRONPOINT>TIME<\/IRONPOINT>/.match(body)[:time]
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
end
