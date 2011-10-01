# encoding: UTF-8
require 'rubygems'
require 'sinatra/base'
require 'haml'
require 'openssl'
['types', 'ituner', 'mc9'].each { |req| require "#{File.dirname(__FILE__)}/#{req}" }

# The Sinatra Web Front End
class Dj9 < Sinatra::Base
  
  set :public, File.dirname(__FILE__) + '/public'
  def ituner; Mc9.ituner; end
  
  # Homepage
  get '/' do
    @current = ituner.now_playing
    @current_id = @current.nil? ? '' : @current.id
    @pos = ituner.current_pos
    @duration = ituner.current_duration
    @time = ituner.track_time
    @state = ituner.state
    
    @seq = ituner.sequence.clone
    @current_dj = ituner.current_dj
    unless @current_dj.nil?
      @seq.delete(@current_dj)
      @seq.unshift(@current_dj)
    end
    
    haml :index
  end

  # Advance to the next DJ
  get '/advance' do
    ituner.safely { ituner.advance }
    redirect '/'
  end

  # Next track
  get '/next' do
    ituner.safely { ituner.next }
    redirect '/'
  end

  # Run
  get '/run' do
    ituner.safely { ituner.start }
    redirect '/'
  end
  
  # Stop
  get '/pause' do
    ituner.safely { ituner.stop }
    redirect '/'
  end
  
end

Dj9.run! if __FILE__ == $0