class CrawlJob
  
  require "net/https"  
  require "uri"
  require "redis"

  @queue = :cobweb_crawl_job

  def self.perform(content_request)
    # change all hash keys to symbols    
    content_request.deep_symbolize_keys
    redis = NamespacedRedis.new(Redis.new, "cobweb-#{content_request[:crawl_id]}")
    @absolutize = Absolutize.new(content_request[:url], :output_debug => false, :raise_exceptions => false, :force_escaping => false, :remove_anchors => true)

    # check we haven't crawled this url before
    unless redis.sismember "crawled", content_request[:url]
      
      # increment counter and check we haven't hit our crawl limit
      redis.incr "crawl-counter"
      crawl_counter = redis.get("crawl-counter").to_i
      queue_counter = redis.get("queue-counter").to_i
      if crawl_counter <= content_request[:crawl_limit]
        content = CobWeb.new(content_request).get(content_request)
        redis.sadd "crawled", content_request[:url] 
        set_base_url redis, content, content_request[:base_url]
        if queue_counter <= content_request[:crawl_limit]
          ap content[:links]
          content[:links].keys.map{|key| content[:links][key]}.flatten.each do |link|
            ap link
            unless redis.sismember "crawled", link
              puts redis.get("base_url")
              puts "---------------------------------"
              if link.match(Regexp.new("^#{redis.get("base_url")}"))
                new_request = content_request.clone
                new_request[:url] = link
                new_request[:parent] = content_request[:url]
                Resque.enqueue(CrawlJob, new_request)
                redis.incr "queue-counter"
              end
            end
          end
        end

        # enqueue to processing queue
        Resque.enqueue(const_get(content_request[:processing_queue]), content)
        puts "#{content_request[:url]} has been sent for processing." if content_request[:debug]
        puts "Crawled: #{crawl_counter} Limit: #{content_request[:crawl_limit]} Queued: #{queue_counter}" if content_request[:debug]

      else
        puts "Crawl Limit Exceeded by #{crawl_counter - content_request[:crawl_limit]} objects" if content_request[:debug]
      end
    else
      puts "Already crawled #{content_request[:url]}" if content_request[:debug]
    end
  end

  private
  def self.set_base_url(redis, content, base_url)
    if redis.get("base_url").nil?
      if content[:status_code] >= 300 and content[:status_code] < 400
        #redirect received for first url
        redis.set("base_url", @absolutize.url(content[:location]).to_s)
        puts "Warning: base_url given redirects to another location, setting base_url to #{@absolutize.url(content[:location]).to_s}"
      else
        redis.set("base_url", base_url)
      end
    end
  end

  
end