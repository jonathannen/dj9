require 'sinatra'

require 'openssl'
require_relative 'ituner'

ituner = Ituner.new.think

# Homepage
get '/' do
  @current = ituner.now_playing
  @current_id = @current.nil? ? '' : @current.id
  @seq = ituner.sequence
  puts "!!!!!"
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
  etag(id) unless (id == 'current') # Yes - the Etag is the ID. We don't expect the artwork to really change  
  track = (id.nil? || id == 'current') ? ituner.now_playing : ituner.track(id)
  (track.nil? || track.artwork.nil?) ? File.open(File.dirname(__FILE__) + '/public/pixel.png', 'rb').read : track.artwork.data
end

# Start a thread to keep things ticking over
Thread.new do
  while true
    begin
      ituner.think
    rescue
    end
    sleep 5
  end
end
