require 'appscript'
require 'chunky_png'
require 'pstore'
require_relative 'types'

# iTunes Controller
class Ituner
  DATABASE_VERSION = 1
  attr_reader :host, :jockey
  
  def initialize
    @host = Appscript.app('iTunes')
    @host.run
    @jockey = ITuneJockey10_5.new(@host)
    @store = PStore.new("tmp/data_#{DATABASE_VERSION}.pstore")
    @state = :run    
  end
  
  # -- Playlist and Sources
  # Advance to to the next DJ in the sequence
  def advance(record = true)
    return if @sequence.nil? || @sequence.empty?

    current = @current || @sequence.first
    @current = upcoming = @sequence.rotate!(1).first

    # Record that this DJs has been played
    @store.transaction { @store[current.id] = PlayRecord.new(current.id, Time.now.utc, 0) } if record

    return if upcoming.nil?
    host.play upcoming.playlists.first, once: true
  end
  
  # The current DJ
  def current
    current_id = now_playing.id
    @current = @sequence.find { |dj| dj.tracks.map(&:id).include?(current_id) }
  end
  
  # Produce a sequence of DJs
  def deejays
    result = []
    host.sources.get.each do |src| 
      # Need at least one playlist named dj9, and it must have tracks in it
      lists = src.playlists.get.select { |pl| (pl.name.get.downcase == 'dj9') && !pl.tracks.get.empty? }
      next if lists.empty?
      result << Deejay.new(src.index.get, src.name.get, src.name.get, lists, lists.first.tracks.get.map { |t| Track.new(t) })
    end
    
    # Sort the DJs by the last time they were played    
    # DJ index is a very low number (i.e. < 100). We use it to get a 
    # reasonably consistent sort for new DJs 
    @store.transaction(true) do
      result.sort_by! { |dj| @store[dj.id].nil? ? Time.now.utc : @store[dj.id].last }
    end
    result
  end
  
  # What's the complete sequence from here. By DJ and Track
  def sequence
    @sequence.clone # Clone as modifications would alter the player state
  end
  
  # -- Player Controls
  def player_state
    @host.player_state.get
  end
  
  def playing?
    self.player_state == :playing
  end
  
  def next
    @host.next_track
  end
  
  def now_playing
    return nil unless playing?
    Track.new(host.current_track.get)
  end
  
  def state
    @state
  end
  
  def stop
    @state == :stop
    @host.stop
  end
  
  def start
    @state == :run
    @host.play
  end

  # Called to assess the player state and act as necessary
  # Generally a background thread will call this periodically
  def think(cache = false)
    verify_sources
    @sequence = deejays
    advance if (@state == :run) && !playing?
    cache_artwork if cache
    return self
  end
  
  # Class method to "safely" interact with the iTuner. Will catch and
  # potentially respond to errors.
  
  protected
  def cache_artwork
    # Cache images if available - and they exist
    candidates = []
    @sequence.map(&:tracks).flatten.each do |track|
      next if track.artwork? || track.artwork.nil? # Artwork already there, or there is none to get
      candidates << track
    end
    return if candidates.empty? # Nothing to get
    
    print '['
    candidates.each do |track|
      print '.'
      STDOUT.flush
      track.cache_artwork
    end
    print ']'
    STDOUT.flush
  end
  
  def verify_sources
    # Shared Libaries available via AppleScript
    libraries = host.sources[Appscript.its.kind.eq(:shared_library)].get
    available = libraries.map { |l| l.name.get }
    
    # Exepected - Libraries visible on the UI
    expected_shared = jockey.scan
    
    # Make sure everything we expect has been activated
    expected_shared.each do |exp|
      next if available.include?(exp.name)      
      print "{#{exp.name}}"
      STDOUT.flush
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
      
      # Skip the headline
      next if ['SHARED', 'Home Sharing'].include?(name)
      # This line will skip if the actual library is open (has their own "Music", etc, etc tabs in it)
      next unless ['0', '1'].include?(row.attributes['AXDisclosureLevel'].get.value.get.to_s)      
      results << NamedWidget.new(name, row) unless results.nil?
    end
    return results    
  end
  
  def activate(lib)
    lib.widget.select
  end
end