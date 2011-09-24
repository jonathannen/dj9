require 'appscript'
require 'chunky_png'
require 'pstore'
# require_relative 'persist'

# Representation of an iTunes Track
Artwork = Struct.new("Artwork", :format, :data)
class Track
  VARIABLES = :name, :time, :artist, :album
  attr_reader :id
  attr_reader *VARIABLES
  
  def initialize(track)
    @track = track
    @id = track.persistent_ID.get
    VARIABLES.each { |v| self.instance_variable_set("@#{v}".to_sym, track.send(v.to_sym).get) }
  end
  
  def artwork
    return @artwork unless @artwork.nil?
    begin
      art = @track.artworks.get.first
      return nil if art.nil?
      @artwork = Artwork.new(art.format.get, art.raw_data.get.data)
      
    # Trap and ignore a common AppleScript error
    rescue Appscript::CommandError => ce
      return nil if ce.error_number == -4
      throw ce
    end
  end
  
  def artwork?
    filename = File.dirname(__FILE__) + "/public/art/#{self.id}_160x160.png"
    File.exists?(filename)
  end
  
  def artwork_path
    artwork? ? "/art/#{self.id}_160x160.png" : '/pixel.png'
  end  
  
  # Cache the artwork. Currently only handles PNG versions
  def cache_artwork
    filename = Track.artwork_directory + "/#{self.id}.png"
    thumb = Track.artwork_directory + "/#{self.id}_160x160.png"    
    data = self.artwork.data
    # The raw data as a PNG file
    File.open(filename, 'wb') { |f| f.write(data) }

    # The thumbnail version
    if self.artwork.format.to_s =~ /PNG/ # We only want PNGs for now 
      ChunkyPNG::Image.from_datastream(ChunkyPNG::Datastream.from_blob(data)).resample_nearest_neighbor!(160, 160).save(thumb)
    else
      File.open(thumb, 'wb') { |f| f.write(data) }      
    end
    return thumb
  end
  
  def self.artwork_directory
    File.dirname(__FILE__) + "/public/art"
  end
  
end

# A DJ is a shared library on the network (+ the local library)
class Deejay < Struct.new("Deejay", :index, :id, :name, :playlists, :tracks)
  def time
    times = tracks.map { |t| t.time.split(':') }
    mins = times.map { |t| t[0].to_i }.inject(0, &:+)
    secs = times.map { |t| t[1].to_i }.inject(0, &:+)    
    "#{'%02d' % (mins + (secs / 60))}:#{'%02d' % (secs % 60)}"
  end
end
# Named widget on the iTunes UI
NamedWidget = Struct.new("NamedWidget", :name, :widget)  
# A saved record of when something was last played
PlayRecord = Struct.new("PlayRecord", :id, :last, :index)

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
    
    print 'Caching artwork: '
    candidates.each do |track|
      print '.'
      track.cache_artwork
      STDOUT.flush
    end
    puts " and we're done!"
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
      puts "Missing \"#{exp.name}\". Going ahead and activating it."
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