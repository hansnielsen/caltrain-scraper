require_relative "caltrain_realtime"

def time_sanity_check(deps)
  actualtime = deps.first.last.last.last
  puts "--- Times should be '#{actualtime}'"
  deps.map do |station, trains|
    trains.each do |train, type, arr, time|
      if time != actualtime
        puts "--- Uhoh! Got departures with an inconsistent time"
        return
      end
    end
  end
  puts "--- Times all look good"
end

if __FILE__ == $0
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
    puts "got departures:"
    puts d.inspect
  end

  puts "looping now"

  loop { t.wait }
end
