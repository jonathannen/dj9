require 'appscript'
require 'chunky_png'
require 'pstore'
require_relative 'types'

# iTunes Controller
class Ituner
  DATABASE_VERSION = 1
  attr_reader :host, :jockey, :state
  
  def initialize
    @host = Appscript.app('iTunes')
    @host.run
    @jockey = ITuneJockey10_5.new(@host)
    @store = PStore.new("tmp/data_#{DATABASE_VERSION}.pstore")
    @state = :run    
  end
  
  # -- Playlist and Sources
  # Advance to to the next DJ in the sequence
  def advance
    return if @sequence.nil?
    upcoming = @sequence.first
    return if upcoming.nil?
    
    # Record that this DJ has been played
    @store.transaction { @store[upcoming.id] = PlayRecord.new(upcoming.id, Time.now.utc, 0) }
    @sequence = deejays
    
    # Queue them up
    host.play upcoming.playlists.first, once: true
  end
  
  # The current DJ
  def current_dj
    current_id = now_playing
    return nil if current_id.nil?
    current_id = current_id.id
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

  def stop
    @state = :stop
    @host.stop
  end
  
  def start
    @state = :run
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
  # potentially respond to errors. Won't catch Exceptions.
  def safely 
    begin
      yield
    rescue StandardError => se       
      STDERR.puts case se.error_number
      when -1719 then "ERROR: Can't connect to iTunes. You need enable 'Access for assistive devices'. Head to System Preferences > Universal Access, then select 'Enable access for assistive devices'."
      else  "ERROR: #{se}"
      end
    end
  end
  
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
    @host.run # Make sure iTunes is running
    
    # Get a handle to scripting events
    se = Appscript.app('System Events').processes['iTunes']
    
    # Is the host minimized? That will break the interaction
    if @host.browser_windows[1].minimized.get
      STDOUT.puts "WARN: The iTunes Window was in 'Mini-Player' mode. We're going to maximize it. For best reliability try to keep the big iTunes window Open."
      @host.browser_windows[1].minimized.set(false)
    end
    # Activation a bit annoying, so disabled for now. Suspect
    # it improves the reliability, however. Might be an option 
    # for pure server environments.
    # @host.browser_windows[1].activate 
    
    # Get the rows on the splitter window on the left
    # This contains the "Shared Libaries" that we'll iterate through
    rows = se.windows[1].scroll_areas[2].outlines[1].rows.get
    
    # Go through the rows detecting the rows that represent Shared Libraries
    # Generally they come after a row named SHARED. They end by GENIUS or
    # PLAYLISTS. We also need to check that the Shared Library isn't open
    # as the entries will show up as well (e.g. 'Music' or 'Radio' inside 
    # 'Steve's Library')
    results = nil    
    rows.each do |row|
      name = row.static_texts[1].name.get
      # break if ['GENIUS', 'PLAYLISTS'].include?(name)      
      results = [] if name == 'SHARED' 
      next if ['SHARED', 'Home Sharing'].include?(name)
      next unless ['0', '1'].include?(row.attributes['AXDisclosureLevel'].get.value.get.to_s)      
      results << NamedWidget.new(name, row) unless results.nil?
    end
    return results    
  end
  
  # Called when the iTuner actually wants to activate / turn on this
  # element.
  def activate(lib)
    lib.widget.select
  end
end