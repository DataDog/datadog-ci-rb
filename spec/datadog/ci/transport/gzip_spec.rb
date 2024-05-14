require_relative "../../../../lib/datadog/ci/transport/gzip"

RSpec.describe Datadog::CI::Transport::Gzip do
  let(:input) do
    <<-LOREM
        ❤️ Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc et est eu dui dignissim tempus. Aliquam
        scelerisque posuere odio id sollicitudin. Etiam dolor lorem, interdum sed mollis consectetur, sagittis a massa.
        Lorem ipsum dolor sit amet, consectetur adipiscing elit. Donec gravida, libero ac gravida ornare, leo elit
        facilisis nunc, in pharetra odio lectus sit amet augue. Cras fermentum interdum tortor, pulvinar laoreet massa
        mollis non. Vestibulum pulvinar dolor nec ante facilisis, in scelerisque tortor maximus.

        Cras pellentesque odio at mauris venenatis efficitur. Mauris pretium, est eu convallis sagittis, felis purus ]
        ullamcorper turpis, vel hendrerit justo massa at nulla. Maecenas hendrerit ante ligula. Maecenas blandit porta
        magna. Proin volutpat vestibulum diam quis malesuada. Aliquam at porttitor turpis. Aliquam ut tellus ultricies,
        commodo sapien vel, consequat felis. Aenean velit turpis, rhoncus in ipsum ut, tempor iaculis nisi. Fusce
        faucibus consequat blandit. Nam maximus augue quis tellus cursus eleifend. Suspendisse auctor, orci sit amet
        vehicula molestie, magna nibh rutrum metus, eget sagittis felis mauris eu quam. Vivamus ut vulputate est.
    LOREM
  end

  describe ".compress" do
    subject { described_class.compress(input) }

    it "compresses" do
      expect(input.size).to be > subject.size
    end

    it "can be decompressed with gzip" do
      Zlib::GzipReader.new(StringIO.new(subject)) do |gzip|
        expect(gzip.read).to eq(input)
      end
    end
  end

  describe ".decompress" do
    subject { described_class.decompress(compressed_input) }

    let(:compressed_input) do
      sio = StringIO.new
      writer = Zlib::GzipWriter.new(sio)
      writer << input
      writer.close
      sio.string
    end

    it "decompresses" do
      expect(subject).to eq(input)
    end
  end
end
