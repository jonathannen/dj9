require 'sinatra'
require_relative 'ituner'

ituner = Ituner.new

# Serve the pages
get '/' do
  current = ituner.now_playing
  # current = ituner.track(current.id)
  "Well Hello. iTunes is currently playing #{current.id} - #{current.name}. Artwork is #{current.artwork.format}" +
  "<img src='/art/1'/>"
end

get '/art/:id' do
  content_type 'image/png'
  track = ituner.now_playing
  track.artwork.data
end