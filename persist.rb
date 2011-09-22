# Persist by writing to a file
module Persist
  
  def load
    begin
      file = File.open(persist_file, 'rb')
      val = file.read
      file.close
      return {} if val.empty?
      Marshal.load(val) || {}
    rescue
      {}
    end
  end
  
  def save(val = @persist)
    val = {} if val.nil?
    file = File.open(persist_file, 'wb')
    file.write(Marshal.dump(val))
    file.close
  end

  def persist_file
    return @_persist_file unless @_persist_file.nil?
    FileUtils.mkdir_p File.dirname(__FILE__) + '/tmp'
    @_persist_file = File.dirname(__FILE__) + '/tmp/data.txt'
  end
  
end