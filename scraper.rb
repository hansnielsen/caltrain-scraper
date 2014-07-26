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

  db.create_table? :readings do
    primary_key :id
    DateTime :created_at
  end

  db.create_table? :stations do
    primary_key :id
    String :name, :text => true
  end

  db.create_table? :trains do
    primary_key :id
    String :name, :text => true
  end

  db.create_table? :types do
    primary_key :id
    String :name, :text => true
  end

  db.create_table? :timepoints do
    primary_key :id
    foreign_key :train_id, :trains
    foreign_key :station_id, :stations
    foreign_key :type_id, :types
    String :arrival, :text => true
    String :time, :text => true
    foreign_key :reading_id, :readings
  end

  db
end

def do_scrape(stations, db)
  puts "retrieving departures"
  d = CaltrainRealtime.get_departures(stations).select {|k,v| v.size > 0}
  time_sanity_check(d)

  reading = Reading.create(:created_at => Time.now)

  d.each do |station, trains|
    trains.each do |train, type, arr, time|
      Timepoint.create(:train => Train.find_or_create(:name => train),
                       :station => Station.find_or_create(:name => station),
                       :type => Type.find_or_create(:name => type),
                       :arrival => arr,
                       :time => time,
                       :reading => reading)
    end
  end
end

if __FILE__ == $0
  db = setup_db

  class Reading < Sequel::Model
    one_to_many :timepoint
  end

  class Station < Sequel::Model
    one_to_many :timepoint
  end

  class Train < Sequel::Model
    one_to_many :timepoint
  end

  class Type < Sequel::Model
    one_to_many :timepoint
  end

  class Timepoint < Sequel::Model
    many_to_one :train
    many_to_one :station
    many_to_one :type
    many_to_one :reading
  end

  stations = CaltrainRealtime.get_stations

  puts "got #{stations.size} stations"

  # use fact that it returns immediately at the start of the minute
  # then sleep for about half a minute, and start the scraping
  CaltrainRealtime.get_start_of_minute
  puts "got start of minute, waiting a bit"
  sleep 15

  t = Timers::Group.new
  t.every(60) do
    do_scrape(stations, db)
  end

  puts "looping now"

  loop { t.wait }
end
