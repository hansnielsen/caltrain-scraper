require_relative "caltrain_realtime"
require "sequel"
require "time"

def convert_times(time)
  now = DateTime.now
  # offset crap is to fix up time zones
  d = DateTime.parse(time).new_offset(now.offset) - now.offset

  diff = (d - now).to_f

  # if it's more than 12 hours ago or 12 hours from now, adjust
  if diff > 0.5
    d = d.prev_day
  elsif diff < -0.5
    d = d.next_day
  end

  if (d - now).abs > 0.5
    raise "tried to fix time #{time} at #{now} but got weird value #{d}"
  end

  d
end

def parse_arrival_time(reading_time, arr)
  m = /\A(\d+) min\.\z/.match(arr)

  raise "unable to parse arrival time '#{arr}'" if m.nil?

  reading_time + Rational(m[1].to_i, 1440)
end

def parse_scraped_times(deps)
  # in case there are no trains
  begin
    actual_time = deps.first.last.last.last
  rescue
    return nil
  end

  deps.map do |station, trains|
    trains.each do |train, type, arr, time|
      if time != actual_time
        raise "inconsistent times in response: '#{time}' vs '#{actual_time}'"
      end
    end
  end

  return convert_times(actual_time)
end

def setup_db
  db = Sequel.sqlite('caltrain.db')

  db.create_table? :readings do
    primary_key :id
    DateTime :created_at
    DateTime :time
    String :raw, :text => true
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
    DateTime :arrival
    foreign_key :reading_id, :readings
  end

  db
end

def do_scrape(stations, db)
  puts "doing scrape at #{Time.now}"

  begin
    bodies = CaltrainRealtime.get_departures(stations)

    departures = Hash[bodies.map do |station, body|
      [station, CaltrainRealtime.process_departure(body)]
    end.reject {|s,d| d.size == 0}]

    # when there are no trains
    if departures.size < 1
      reading = Reading.create(:created_at => DateTime.now)
      return
    end

    db.transaction do
      reading_time = parse_scraped_times(departures)
      created_at = DateTime.now
      puts "got reading time #{reading_time} and creation time #{created_at}"
      reading = Reading.create(:created_at => created_at, :time => reading_time)

      departures.each do |station, trains|
        trains.each do |train, type, arr, time|
          arrival_time = parse_arrival_time(reading_time, arr)
          Timepoint.create(:train => Train.find_or_create(:name => train),
                           :station => Station.find_or_create(:name => station),
                           :type => Type.find_or_create(:name => type),
                           :arrival => arrival_time,
                           :reading => reading)
        end
      end
    end
  rescue => e
    puts "oh no! #{e}"
    puts e.backtrace.join("\n")

    Reading.create(:created_at => DateTime.now, :raw => bodies.inspect)
  end
  puts "scrape complete"
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

  begin
    stations = CaltrainRealtime.get_stations
  rescue => e
    puts "unable to get stations: #{e}"
    puts e.backtrace.join("\n")
    exit(0)
  end

  # use fact that it returns immediately at the start of the minute
  # then sleep for about half a minute, and start the scraping
  CaltrainRealtime.get_start_of_minute
  puts "got start of minute, waiting a bit"
  sleep 10

  t = Timers::Group.new
  t.every(60) do
    do_scrape(stations, db)
  end

  puts "starting scrape"
  do_scrape(stations, db)
  loop { t.wait }
end
