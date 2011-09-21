require 'appscript'
Artwork = Struct.new("Artwork", :format, :data)
class Track
  attr_reader :id, :name
  def initialize(track)
    @track = track
    @id = track.persistent_ID.get
    @name = track.name.get
  end
  
  def artwork
    a = @track.artworks.get.first
    return nil if a.nil?
    @artwork ||= Artwork.new(a.format.get, a.data_.get.data)    
  end
end

class Ituner
  
  def initialize
    @it = Appscript.app('iTunes')
    @it.run
    @library = @it.playlists['Library']
  end
  
  def player_state
    @it.player_state.get
  end
  
  def now_playing
    return nil unless player_state == :playing
    Track.new(@it.current_track.get)
  end

  def scan
  end  
  
  def track(id)
  end
  
  # 
  # def track(id)
  #   track = @library.tracks[Appscript.its.persistent_ID.eq(id)]
  #   # app('TextEdit').documents[its.text.eq("\n")]    
  #   # track = @it.tracks.persistent_ID[id].get
  #   return marshall_track(track)
  # end

    
end