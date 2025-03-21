# frozen_string_literal: true

SpiedMetric = Struct.new(:name, :value, :tags)

# no-dd-sa:ruby-best-practices/top-level-methods
def telemetry_spy_value_suffix(value)
  return "" if value.nil?
  " with value = [#{value}]"
end

# spy on telemetry metrics emitted
RSpec.shared_context "Telemetry spy" do
  before do
    @metrics = {
      inc: [],
      distribution: []
    }

    allow(Datadog::CI::Utils::Telemetry).to receive(:inc) do |metric_name, count, tags|
      @metrics[:inc] << SpiedMetric.new(metric_name, count, tags)
    end

    allow(Datadog::CI::Utils::Telemetry).to receive(:distribution) do |metric_name, value, tags|
      @metrics[:distribution] << SpiedMetric.new(metric_name, value, tags)
    end
  end

  shared_examples_for "emits telemetry metric" do |metric_type, metric_name, value = nil|
    it "emits :#{metric_type} metric #{metric_name}#{telemetry_spy_value_suffix(value)}" do
      subject

      metric = telemetry_metric(metric_type, metric_name)
      expect(metric).not_to be_nil

      if value
        expect(metric.value).to eq(value)
      end
    end
  end

  shared_examples_for "emits no metric" do |metric_type, metric_name|
    it "emits no :#{metric_type} metric #{metric_name}" do
      subject

      metric = telemetry_metric(metric_type, metric_name)
      expect(metric).to be_nil
    end
  end

  def telemetry_metric(type, name)
    @metrics[type].find { |m| m.name == name }
  end

  def reset_telemetry_spy!
    @metrics = {
      inc: [],
      distribution: []
    }
  end

  def received_telemetry_metric?(type, name)
    @metrics[type].map(&:name).include?(name)
  end
end
