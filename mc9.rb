['types', 'ituner', 'dj9'].each { |req| require_relative req }

# Master of Ceremonies - Controls the background thread that keeps
# everything ticking over.
class Mc9
  
  class << self
    
    def ituner
      @ituner ||= Ituner.new.think(false)
    end
    
    def exec
      counter = 0
      @running = true
      while @running 
        self.scan(counter == 0) # Scan, performing the asset cache every ~5 times
        counter = counter > 4 ? 0 : counter + 1
        sleep 5
      end
      true
    end
    
    def run!
      ituner
      return Thread.new &:exec
    end
    
    def stop
      @running = false
    end
    
    protected    
    def scan(cache)
      begin
        STDOUT.print "?"
        self.ituner.think(cache)
        STDOUT.puts "!"
      rescue Appscript::CommandError => ce       
        message = case 
        when (ce.error_number == -1719) && (ce.error_message =~ /assistive devices/) then 
          "ERROR: Can't connect to iTunes. You need enable 'Access for assistive devices'. Head to System Preferences > Universal Access, then select 'Enable access for assistive devices'."
        else
          "MC9.ERROR: #{ce}"
        end
        STDERR.puts message
      rescue Exception => e
        STDERR.puts "Unrecoverable Exception raised: #{e}"
        self.stop
      end
    end

  end

end

Mc9.exec if __FILE__ == $0