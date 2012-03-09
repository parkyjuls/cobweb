class Robots
  
  def initialize(url, file_name="robots.txt")
    uri = URI.parse(url)
    [uri.scheme, "://", uri.host, ":", uri.port, "/", file_name].join
    Cobweb.new(:cache => 6000).get([uri.scheme, "://", uri.host, ":", uri.port, "/", file_name].join)
    
  end
end