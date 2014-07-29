require "rest_client"
require "nokogiri"

class Realtime511
  def initialize(token)
    @token = token
  end

  #https://services.my511.org/Transit2.0/GetAgencies.aspx?token=...
  def get_agencies()
    # gets the list of agencies, we want "Caltrain"

    a = RestClient.get "http://services.my511.org/Transit2.0/GetAgencies.aspx", :params => {:token => @token}
    xa = Nokogiri.XML(a)
    xa.xpath('/RTT/AgencyList/Agency').map {|n| n["Name"]}
  end

  #https://services.my511.org/Transit2.0/GetRoutesForAgency.aspx?token=...&agencyName=Caltrain
  def get_routes(agency)
    # get the list of routes and directions, we want the cross-product

    r = RestClient.get "http://services.my511.org/Transit2.0/GetRoutesForAgency.aspx", :params => {:token => @token, :agencyName => agency}
    xr = Nokogiri.XML(r)
    routes = Hash[xr.xpath('/RTT/AgencyList/Agency[@Name="' + agency + '"]/RouteList/Route').map do |r|
        [r["Code"], r.xpath("RouteDirectionList/RouteDirection").map {|rd| rd["Code"]}]
    end]

    allidfs = routes.map {|n, d| d.map {|dd| [agency, n, dd].join("~")}}.flatten.join("|")
  end

  #https://services.my511.org/Transit2.0/GetStopsForRoutes.aspx?token=...&routeIDF=Caltrain~LOCAL~NB|Cal...
  def get_stops(directions)
    # get the list of stops per direction

    s = RestClient.get "http://services.my511.org/Transit2.0/GetStopsForRoutes.aspx", :params => {:token => @token, :routeIDF => directions}
    xs = Nokogiri.XML(s)

    stoplist = xs.xpath("//Stop").map {|s| s["StopCode"]}.uniq

    # for a full list of stops with sorta-random SB codes
    stops = xs.xpath("//RouteDirection[@Code]").map do |rd|
        rd.xpath("StopList/Stop").map do |s|
            [s["StopCode"], s["name"], rd["Code"]]
        end
    end.flatten(1).uniq {|x| x.first}
  end

  #https://services.my511.org/Transit2.0/GetNextDeparturesByStopCode.aspx?token=...&stopcode=70242
  def get_departures(stopcode)
      # get the next departures at a stop
      d = RestClient.get "http://services.my511.org/Transit2.0/GetNextDeparturesByStopCode.aspx", :params => {:token => @token, :stopcode => stopcode}
      xd = Nokogiri.XML(d)
      #d.xpath # XXX parse times better
  end
end
