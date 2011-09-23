require 'appscript'
require 'chunky_png'
require_relative 'persist'

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
    a = @track.artworks.get.first
    return nil if a.nil?
    @artwork ||= Artwork.new(a.format.get, a.raw_data.get.data)    
  end  
  
  def artwork?
    filename = File.dirname(__FILE__) + "/public/art/#{self.id}_160x160.png"
    File.exists?(filename)
  end
  
end

# Named Widgets
class Deejay < Struct.new("Deejay", :index, :id, :name, :playlists, :tracks)
  def time
    times = tracks.map { |t| t.time.split(':') }
    mins = times.map { |t| t[0].to_i }.inject(0, &:+)
    secs = times.map { |t| t[1].to_i }.inject(0, &:+)
    mins += secs / 60
    secs = secs % 60
    "#{mins}:#{secs}"
  end
end
NamedWidget = Struct.new("NamedWidget", :name, :widget)

# iTunes Controller
class Ituner
  include Persist
  
  attr_reader :host, :jockey
  
  def initialize
    @host = Appscript.app('iTunes')
    @host.run
    @jockey = ITuneJockey10_5.new(@host)
    @current = nil
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
      current = @current || @sequence.first
      data = load
      data[current.id] = Time.now.utc
      save(data)
    end
    @current = upcoming = @sequence.rotate!(1).first
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
  
  def artwork(track_id)
    filename = artwork_directory + "/#{track_id}_160x160.png"
    return nil unless File.exists?(filename)
    file = File.open(filename, 'rb')
    data = file.read
    file.close
    return data
  end

  # Called to assess the player state and act as necessary
  # Generally a background thread will call this periodically
  def think(cache = true)
    verify_sources
    @sequence = deejays
    
    if playing?
      current_id = now_playing.id
      @current = @sequence.find { |dj| dj.tracks.map(&:id).include?(current_id) }
    else      
      advance if (@state == :run)
    end
    
    # Cache images if available - and they exist
    if cache      
      # puts @sequence.map(&:tracks).flatten.inspect
      print 'Caching artwork: '
      @sequence.map(&:tracks).flatten.each do |track|
        begin
          filename = artwork_directory + "/#{track.id}.png"
          thumb = artwork_directory + "/#{track.id}_160x160.png"
          next if File.exists?(thumb)        
          next if track.artwork.nil?
          data = track.artwork.data
          next if data.nil?

          file = File.open(filename, 'wb')
          file.write(data)
          file.close
        
          if track.artwork.format.to_s =~ /PNG/        
            print '.'
            # Plus a thumb
            png = ChunkyPNG::Image.from_datastream(ChunkyPNG::Datastream.from_blob(data))
            png.resample_nearest_neighbor!(160, 160)
            png.save(thumb)
          else
            print '-'
            file = File.open(thumb, 'wb')
            file.write(data)
            file.close
          end          
        rescue StandardError => e
          print 'x'
        end
        STDOUT.flush
      end
      puts " Done"
    end
    
    return self
  end
  
  protected
  def artwork_directory
    tmp = File.dirname(__FILE__) + '/public/art'
    FileUtils.mkdir_p tmp
    tmp
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
      next if ['SHARED', 'Home Sharing'].include?(name)
      results << NamedWidget.new(name, row) if !results.nil?
    end
    return results    
  end
  
  def activate(lib)
    lib.widget.select
  end
end