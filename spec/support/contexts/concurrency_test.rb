# Concurreny test shared context sets up the concurrency test environment.
#
# It provides some convenience methods to run code concurrently in tests, such as:
# - repeat: run a block of code multiple times
# - run_concurrently: run a block of code concurrently in multiple threads
RSpec.shared_context "Concurrency test" do
  let(:threads_count) { 10 }
  let(:repeat_count) { 20 }

  def repeat
    repeat_count.times do
      yield
    end
  end

  def run_concurrently
    (1..threads_count).map do
      Thread.new do
        yield
      end
    end.map(&:join)
  end
end
