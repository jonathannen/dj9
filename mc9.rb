# Master of Ceremonies - Controls the background thread that keeps
# everything ticking over.
class Mc9
  
  class << self
    
    def ituner
      @ituner ||= Ituner.new.think(false)
    end
    
    def run!
      ituner
      Thread.new do
        counter = 0
        @running = true
        while @running 
          self.scan(counter == 0) # Scan, performing the asset cache every ~5 times
          counter = counter > 4 ? 0 : counter + 1
          sleep 5
        end
        true
      end
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
      rescue StandardException => se       
        STDERR.puts case se.error_number
        when -1719 then "ERROR: Can't connect to iTunes. You need enable 'Access for assistive devices'. Head to System Preferences > Universal Access, then select 'Enable access for assistive devices'."
        else  "MC9.ERROR: #{se}"
        end
      rescue Exception => e
        STDERR.puts "Unrecoverable Exception raised: #{e}"
        self.stop
      end
    end

  end

end