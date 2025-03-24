require "spec_helper"
require "datadog/ci/utils/file_storage"

RSpec.describe Datadog::CI::Utils::FileStorage do
  let(:temp_dir) { described_class::TEMP_DIR }
  let(:test_key) { "test_key" }
  let(:test_value) { {"key" => "value", "array" => [1, 2, 3], "nested" => {"data" => true}} }
  let(:file_path) { File.join(temp_dir, "dd-ci-#{test_key}.dat") }

  # Clean up any test files before and after tests
  before(:each) do
    described_class.cleanup
    # Reset any previous logger stubs
    allow(Datadog.logger).to receive(:error).and_call_original
  end

  after(:each) do
    described_class.cleanup
  end

  describe ".store" do
    context "when storing data successfully" do
      it "creates the storage directory" do
        expect(Dir.exist?(temp_dir)).to be false
        described_class.store(test_key, test_value)
        expect(Dir.exist?(temp_dir)).to be true
      end

      it "creates a file with the correct name" do
        described_class.store(test_key, test_value)
        expect(File.exist?(file_path)).to be true
      end

      it "returns true on success" do
        expect(described_class.store(test_key, test_value)).to be true
      end

      it "stores different types of data" do
        [
          "string value",
          123,
          [1, 2, 3],
          {a: 1, b: 2},
          true,
          false,
          nil,
          Object.new,
          Set.new([1, 2, 3])
        ].each do |value|
          key = "test_#{value.class.name.downcase}"
          expect(described_class.store(key, value)).to be true
        end
      end

      it "handles keys with special characters" do
        special_key = "test/key with:special@characters!"
        sanitized_path = File.join(temp_dir, "dd-ci-test_key_with_special_characters_.dat")

        described_class.store(special_key, test_value)
        expect(File.exist?(sanitized_path)).to be true
      end

      it "overwrites existing data for the same key" do
        described_class.store(test_key, "original value")
        described_class.store(test_key, "new value")

        result = described_class.retrieve(test_key)
        expect(result).to eq("new value")
      end
    end

    context "when storing data fails" do
      before do
        allow(File).to receive(:binwrite).and_raise(IOError.new("Test IO error"))
      end

      it "returns false on failure" do
        expect(described_class.store(test_key, test_value)).to be false
      end

      it "logs an error message" do
        expect(Datadog.logger).to receive(:error).with(/Failed to store data for key 'test_key': IOError - Test IO error/).once
        described_class.store(test_key, test_value)
      end
    end

    context "when marshalling fails" do
      before do
        # Mock Marshal.dump to raise an error
        allow(Marshal).to receive(:dump).and_raise(TypeError.new("can't dump anonymous class"))
      end

      it "returns false on marshalling failure" do
        expect(described_class.store(test_key, test_value)).to be false
      end

      it "logs an error message" do
        expect(Datadog.logger).to receive(:error).with(/Failed to store data for key 'test_key': TypeError - can't dump anonymous class/).once
        described_class.store(test_key, test_value)
      end
    end
  end

  describe ".retrieve" do
    context "when retrieving existing data" do
      before do
        described_class.store(test_key, test_value)
      end

      it "returns the stored data" do
        result = described_class.retrieve(test_key)
        expect(result).to eq(test_value)
      end

      it "preserves complex data structures" do
        complex_data = {
          string: "test",
          number: 42,
          array: [1, 2, 3],
          hash: {a: 1, b: 2},
          nested: {array: [{key: "value"}]}
        }

        described_class.store(test_key, complex_data)
        result = described_class.retrieve(test_key)

        expect(result).to eq(complex_data)
      end
    end

    context "when the file does not exist" do
      it "returns nil" do
        expect(described_class.retrieve("nonexistent_key")).to be_nil
      end
    end

    context "when reading the file fails" do
      before do
        described_class.store(test_key, test_value)
        allow(File).to receive(:binread).and_raise(IOError.new("Test IO error"))
      end

      it "returns nil on failure" do
        expect(described_class.retrieve(test_key)).to be_nil
      end

      it "logs an error message" do
        expect(Datadog.logger).to receive(:error).with(/Failed to retrieve data for key 'test_key': IOError - Test IO error/).once
        described_class.retrieve(test_key)
      end
    end

    context "when unmarshalling fails" do
      before do
        # Create a corrupted file
        described_class.ensure_temp_dir_exists
        File.binwrite(file_path, "corrupted data")
      end

      it "returns nil on unmarshalling failure" do
        expect(described_class.retrieve(test_key)).to be_nil
      end

      it "logs an error message" do
        expect(Datadog.logger).to receive(:error).with(/Failed to retrieve data for key 'test_key': TypeError/).once
        described_class.retrieve(test_key)
      end
    end
  end

  describe ".cleanup" do
    context "when the directory exists" do
      before do
        # Create some test files
        described_class.store("key1", "value1")
        described_class.store("key2", "value2")
      end

      it "removes the entire directory" do
        expect(Dir.exist?(temp_dir)).to be true
        described_class.cleanup
        expect(Dir.exist?(temp_dir)).to be false
      end

      it "returns true on success" do
        expect(described_class.cleanup).to be true
      end
    end

    context "when the directory does not exist" do
      it "returns false" do
        # Make sure directory doesn't exist
        FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)

        expect(described_class.cleanup).to be false
      end
    end
  end

  describe ".file_path_for" do
    it "sanitizes keys with special characters" do
      special_key = "test/key with:special@characters!"
      expected_path = File.join(temp_dir, "dd-ci-test_key_with_special_characters_.dat")

      expect(described_class.send(:file_path_for, special_key)).to eq(expected_path)
    end

    it "handles numeric keys" do
      numeric_key = 12345
      expected_path = File.join(temp_dir, "dd-ci-12345.dat")

      expect(described_class.send(:file_path_for, numeric_key)).to eq(expected_path)
    end

    it "handles symbol keys" do
      symbol_key = :test_symbol
      expected_path = File.join(temp_dir, "dd-ci-test_symbol.dat")

      expect(described_class.send(:file_path_for, symbol_key)).to eq(expected_path)
    end
  end

  describe ".ensure_temp_dir_exists" do
    before do
      # Make sure directory doesn't exist
      FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
    end

    it "creates the directory if it doesn't exist" do
      expect(Dir.exist?(temp_dir)).to be false
      described_class.send(:ensure_temp_dir_exists)
      expect(Dir.exist?(temp_dir)).to be true
    end

    it "doesn't raise an error if the directory already exists" do
      FileUtils.mkdir_p(temp_dir)
      expect { described_class.send(:ensure_temp_dir_exists) }.not_to raise_error
    end

    context "when creating the directory fails" do
      before do
        allow(FileUtils).to receive(:mkdir_p).and_raise(SystemCallError.new("Permission denied", 13))
      end

      it "raises the error" do
        expect { described_class.send(:ensure_temp_dir_exists) }.to raise_error(SystemCallError)
      end
    end
  end
end
