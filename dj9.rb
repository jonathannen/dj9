require 'sinatra'

require 'openssl'
require_relative 'ituner'

ituner = Ituner.new.think(false)

# Homepage
get '/' do
  @current = ituner.now_playing
  @current_id = @current.nil? ? '' : @current.id
  @seq = ituner.sequence
  haml :index
end

# Advance to the next DJ
get '/advance' do
  ituner.advance
  redirect '/'
end

# Next track
get '/next' do
  ituner.next
  redirect '/'
end

# Track Art
get '/track/:id/art' do
  content_type 'image/png'
  id = params[:id]
  id = ituner.now_playing.id if (id == 'current')
  data = ituner.artwork(id)
  etag data.length.to_s unless data.nil?
  data = File.open(File.dirname(__FILE__) + '/public/pixel.png', 'rb').read if data.nil?
  return data
end

# Start a thread to keep things ticking over
Thread.new do
  while true
    begin
      print "think? "
      STDOUT.flush
      ituner.think
    rescue StandardError => e
      puts "ERROR: " + e.inspect
    end
    sleep 5
  end
end
