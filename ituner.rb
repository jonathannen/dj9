require 'appscript'
require_relative 'persist'

# Representation of an iTunes Track
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

# Named Widgets
Deejay = Struct.new("Deejay", :index, :id, :name, :playlists, :tracks)
NamedWidget = Struct.new("NamedWidget", :name, :widget)

# iTunes Controller
class Ituner
  include Persist
  
  attr_reader :host, :jockey
  
  def initialize
    @host = Appscript.app('iTunes')
    @host.run
    @jockey = ITuneJockey10_5.new(@host)
    @state = :run    
  end
  
  def configure
    @sequence = deejays
    return self
  end
  
  # -- Playlist and Sources
  def advance(record = true)
    return if @sequence.nil? || @sequence.empty?
    if record
      current = @sequence.first
      data = load
      data[current.id] = Time.now.utc
      save(data)
    end
    upcoming = @sequence.rotate!(1).first
    return if upcoming.nil?
    host.play upcoming.playlists.first, once: true
  end
  
  def deejays
    result = []
    host.sources.get.each do |src| 
      list = filter(src.playlists.get)
      next if list.empty?
      result << Deejay.new(src.index.get, src.name.get, src.name.get, list, list.first.tracks.get.map { |t| Track.new(t) })
    end
    
    # Sort the DJs by the last time they were played    
    # DJ index is a very low number (i.e. < 100). We use it to get a 
    # reasonably consistent sort for new DJs 
    data = load
    result.sort_by! { |dj| (data[dj.id] = data[dj.id] || dj.index).to_i }
    save(data)
    result
  end
  
  def start
    host.play sequence.first.playlists.first, once: true
  end
  
  def filter(playlists)
    playlists.select { |pl| pl.name.get =~ /dj9/ }
  end
  
  # What's the complete sequence from here. By DJ and Track
  def sequence
    @sequence.clone # Clone as modifications would alter the player state
  end
  
  # -- Player Controls
  def player_state
    @host.player_state.get
  end
  
  def playing?; self.player_state == :playing; end
  
  def next
    @host.next_track
  end
  
  def now_playing
    return nil unless playing?
    Track.new(host.current_track.get)
  end
  
  def track(id)
    sequence.each do |deejay|
      deejay.tracks.each { |t| return t if t.id == id }
    end
    return nil
  end
  
  # -- Called to assess the player state
  def think
    verify_sources
    @sequence = deejays
    advance if (@state == :run) && !playing?
    return self
  end
  
  protected
  def verify_sources
    # Shared Libaries available via AppleScript
    libraries = host.sources[Appscript.its.kind.eq(:shared_library)].get
    available = libraries.map { |l| l.name.get }
    
    # Exepected - Libraries visible on the UI
    expected_shared = jockey.scan
    
    # Make sure everything we expect has been activated
    expected_shared.each do |exp|
      next if available.include?(exp.name)
      puts "Missing Library #{exp.name}. Going ahead and activating it."
      jockey.activate(exp)
    end
  end
     
end

# Specific sharing activations for iTunes versions
class ITuneJockey10_5
  def initialize(host)
    @host = host
  end 
  def scan
    @host.run
    se = Appscript.app('System Events').processes['iTunes'].windows[1].scroll_areas[2].outlines[1].rows.get
    results = nil    
    se.each do |row|
      name = row.static_texts[1].name.get
      break if ['GENIUS', 'PLAYLISTS'].include?(name)
      results = [] if name == 'SHARED'
      results << NamedWidget.new(name, row) if !results.nil? && name =~ /.*\sLibrary\z/ 
    end
    return results    
  end
  
  def activate(lib)
    lib.widget.select
  end
end