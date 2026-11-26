# Ruby kills the thread when the process exits, after the exit handlers, and the thread
# then loads leaf.rb.
started = Queue.new
Thread.new do
  started << true
  sleep
ensure
  load File.expand_path("leaf.rb", __dir__)
end
started.pop
