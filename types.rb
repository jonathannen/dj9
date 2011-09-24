require 'base64'
require 'chunky_png'

# A
# Representation of an iTunes Track
Artwork = Struct.new("Artwork", :format, :data)

# D
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

# T
# Track
class Track
  VARIABLES = :name, :time, :artist, :album, :album_artist
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
    filename = File.dirname(__FILE__) + "/public/art/T#{self.id}_160x160.png"
    File.exists?(filename)
  end
  
  def artwork_path
    artwork? ? "/art/T#{self.id}_160x160.png" : '/pixel.png'
  end  
  
  def album_artwork?
    filename = File.dirname(__FILE__) + "/public/art/A#{album_artwork_name}_160x160.png"
    File.exists?(filename)
  end
  
  def album_artwork_path
    album_artwork? ? "/art/A#{album_artwork_name}_160x160.png" : '/pixel.png'
  end
  
  def album_artwork_name
    ["#{self.artist}-#{self.album}"].pack('m').tr("+/", "-_")[0..-2]
    # Base64.urlsafe_encode64()
  end
  
  # Cache the artwork. Currently only handles PNG versions
  def cache_artwork
    filename = Track.artwork_directory + "/T#{self.id}.png"
    thumb = Track.artwork_directory + "/T#{self.id}_160x160.png"    
    data = self.artwork.data
        
    # Write the track level data
    write_artwork(data, filename, thumb)
    # Also write the album data
    write_artwork(data, Track.artwork_directory + "/A#{album_artwork_name}.png", Track.artwork_directory + "/A#{album_artwork_name}_160x160.png" )    
    return thumb
  end
  
  def self.artwork_directory
    File.dirname(__FILE__) + "/public/art"
  end
  
  protected
  def write_artwork(data, filename, thumb)
    # The raw data as a PNG file
    File.open(filename, 'wb') { |f| f.write(data) }

    # The thumbnail version
    if self.artwork.format.to_s =~ /PNG/ # We only want PNGs for now 
      ChunkyPNG::Image.from_datastream(ChunkyPNG::Datastream.from_blob(data)).resample_nearest_neighbor!(160, 160).save(thumb)
    else
      File.open(thumb, 'wb') { |f| f.write(data) }      
    end
  end
  
end