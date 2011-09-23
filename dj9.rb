require 'sinatra/base'
require 'openssl'
require_relative 'ituner'
require_relative 'mc9'

# The Sinatra Web Front End
class Dj9 < Sinatra::Base
  
  set :public, File.dirname(__FILE__) + '/public'
  def ituner; Mc9.ituner; end
  
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
  
end

# Kick off the back, then kick off the front
Mc9.run!
Dj9.run! if ($0 == __FILE__) # Run if this is from the command line