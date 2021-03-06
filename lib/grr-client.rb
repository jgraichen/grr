this_dir = File.expand_path(File.dirname(__FILE__))
lib_dir = File.join(this_dir)
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)

require "grpc"
require "service/rest_services_pb"
require "concurrent"
require "logger"
require "json"
require "util/outUtil"

module Grr
  class Client

    def initialize(**kwargs)
      host = kwargs.fetch(:Host, "0.0.0.0")
      port = kwargs.fetch(:Port, "50051")
      url = "#{host}:#{port}"
      @util = Grr::OutUtil.new("gRPC",logger)
      # create client stub for the specified pb service
      @stub = Grr::RestService::Stub.new(url, :this_channel_is_insecure)
    end

    # Takes a Request Object and executes it
    def request(req, idx = nil)
      t1 = Time.now
      # logger.info("Start REST request")
      resp = @stub.do_request(req)
      t2 = Time.now
      msecs = time_diff_milli t1, t2
      logger.info("[#{idx}] Received Response #{resp.status} in #{msecs}ms")
      return resp, msecs
    rescue GRPC::BadStatus, StandardError => e
      if e.code
        logger.error("[#{idx}] Error from Server. Code: #{e.code} Details: #{e.details}")
      end

      if e.message
        logger.error e.message
      else
        logger.error e
      end

      false
    end

    # Takes an array of Requests and executes them in parallel
    def concurrentRequests requestArray, threads = 5
      #pool = Concurrent::CachedThreadPool.new
      @util.printBenchmarkStart requestArray.size,threads
      successful = 0
      failed = 0
      totalTime = 0
      pool = Concurrent::ThreadPoolExecutor.new(
         min_threads: threads,
         max_threads: threads,
         max_queue: 100000,
         fallback_policy: :abort
      )

      logger.info("Thread pool opened")
      t1 = Time.now
      requestArray.each_with_index {|sId, idx|
          pool.post do
              response, msecs = request sId, idx
              if response && response.status < 400
                successful += 1
                totalTime += msecs
              else
                failed += 1
              end
        end
      }
      pool.shutdown
      pool.wait_for_termination
      t2 = Time.now
      msecs = time_diff_milli t1, t2
      @util.printBenchmarkEnd requestArray.size,threads,successful,failed,msecs,totalTime
    end

    private
    def time_diff_milli start, finish
      (finish - start) * 1000.0
    end

    private
    def logger
      @logger ||= Logger.new(STDOUT)
    end
  end
end
