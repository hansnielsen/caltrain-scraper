require "curb"
require "nokogiri"

class CaltrainMobile
  BaseURL = "http://www.caltrain.com/"
  StationPath = "/schedules/realtime/stations.html"

  def self.get_departures(stations)
    stuff = stations.map do |path, name|
      {
        :url => URI.join(BaseURL, path).to_s,
        :post_fields => {
          "__EVENTTARGET" => "",
          "__CALLBACKID" => "ctl01",
          "__CALLBACKPARAM" => "refreshStation=#{name}"
        }
      }
    end

    departures = {}
    Curl::Multi.post(stuff, {}, {:pipeline => true}) do |e|
      path = URI(e.last_effective_url).path
      departures[path] = process_departure(e.body)
    end
    departures
  end

  def self.get_departure(path, name)
    body = Curl.post("http://www.caltrain.com/" + path, {"__EVENTTARGET" => "", "__CALLBACKID" => "ctl01", "__CALLBACKPARAM" => "refreshStation=#{name}"}).body

    process_departure(body)
  end

  def self.get_station_names(paths)
    urls = paths.map {|p| URI.join(BaseURL, p).to_s}
    stations = {}
    Curl::Multi.get(urls, {}, {:pipeline => true}) do |e|
      path = URI(e.last_effective_url).path
      name = /ipjstGetTrainInfo\('(?<name>[^']+)'\)/.match(e.body)[:name]
      stations[path] = name
    end
    stations
  end

  def self.get_stations(path=StationPath)
    body = Curl.get(URI.join(BaseURL, path).to_s).body

    paths = process_station_paths(body)
    get_station_names(paths)
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

  def self.process_station_paths(body)
    xml = Nokogiri.HTML(body)
    xml.xpath("//p/a").map do |s|
      s["href"]
    end
  end
end
