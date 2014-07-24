require_relative "caltrain_realtime"
require "sequel"

def time_sanity_check(deps)
  # in case there are no trains
  begin
    actualtime = deps.first.last.last.last
  rescue
    return true
  end
  puts "--- Times should be '#{actualtime}'"
  deps.map do |station, trains|
    trains.each do |train, type, arr, time|
      if time != actualtime
        puts "--- Uhoh! Got departures with an inconsistent time"
        return false
      end
    end
  end

  puts "--- Times all look good"
  true
end

def setup_db
  db = Sequel.sqlite('caltrain.db')

  db.create_table? :timepoints do
    primary_key :id

    String :train, :text => true
    String :station, :text => true
    String :type, :text => true
    String :arrival, :text => true
    String :time, :text => true
  end

  db
end

if __FILE__ == $0
  db = setup_db

  stations = CaltrainRealtime.get_stations

  puts "got #{stations.size} stations"

  # use fact that it returns immediately at the start of the minute
  # then sleep for about half a minute, and start the scraping
  CaltrainRealtime.get_start_of_minute
  puts "got start of minute, waiting a bit"
  sleep 15

  t = Timers::Group.new
  t.every(60) do
    puts "retrieving departures"
    d = CaltrainRealtime.get_departures(stations).select {|k,v| v.size > 0}
    time_sanity_check(d)
    timepoints = db[:timepoints]
    d.each do |station, trains|
      trains.each do |train, type, arr, time|
        timepoints.insert(:train => train, :station => station, :type => type, :arrival => arr, :time => time)
      end
    end
  end

  puts "looping now"

  loop { t.wait }
end
