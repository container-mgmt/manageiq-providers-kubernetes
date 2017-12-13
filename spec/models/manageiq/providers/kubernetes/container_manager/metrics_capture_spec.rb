describe ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture do
  before do
    @ems_kubernetes = FactoryGirl.create(
      :ems_kubernetes,
      :connection_configurations => [{:endpoint       => {:role => :hawkular},
                                      :authentication => {:role => :hawkular}}],
    )

    @node = FactoryGirl.create(:kubernetes_node,
                               :name                  => 'node',
                               :ext_management_system => @ems_kubernetes,
                               :ems_ref               => 'target')

    @node.computer_system.hardware = FactoryGirl.create(
      :hardware,
      :cpu_total_cores => 2,
      :memory_mb       => 2048)

    @group = FactoryGirl.create(:container_group,
                                :ext_management_system => @ems_kubernetes,
                                :container_node        => @node,
                                :ems_ref               => 'group')

    @container = FactoryGirl.create(:kubernetes_container,
                                    :name                  => 'container',
                                    :container_group       => @group,
                                    :ext_management_system => @ems_kubernetes,
                                    :ems_ref               => 'target')
  end

  context "#perf_collect_metrics" do
    it "fails when no ems is defined" do
      @node.ext_management_system = nil
      expect { @node.perf_collect_metrics('interval_name') }.to raise_error(described_class::TargetValidationError)
    end

    it "fails when no cpu cores are defined" do
      @node.hardware.cpu_total_cores = nil
      expect { @node.perf_collect_metrics('interval_name') }.to raise_error(described_class::TargetValidationError)
    end

    it "fails when memory is not defined" do
      @node.hardware.memory_mb = nil
      expect { @node.perf_collect_metrics('interval_name') }.to raise_error(described_class::TargetValidationError)
    end

    # TODO: include also sort_and_normalize in the tests
    METRICS_EXERCISES = [
      {
        :counters           => [
          {
            :args => 'cpu/usage',
            :data => [
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 0},
              {'start' => 1_446_500_060_000, 'end' => 1_446_500_120_000, 'min' => 12_000_000_000},
            ]
          },
          {
            :args => 'network/tx',
            :data => [
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 0},
              {'start' => 1_446_500_060_000, 'end' => 1_446_500_120_000, 'min' => 460_800}
            ]
          },
          {
            :args => 'network/rx',
            :data => [
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 0},
              {'start' => 1_446_500_060_000, 'end' => 1_446_500_120_000, 'min' => 153_600}
            ]
          }
        ],
        :gauges             => [
          {
            :args => 'memory/usage',
            :data => [
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 1_073_741_824}
            ]
          }
        ],
        :node_expected      => {
          Time.at(1_446_500_000).utc => {
            "cpu_usage_rate_average"     => 10.0,
            "mem_usage_absolute_average" => 50.0,
            "net_usage_rate_average"     => 10.0
          }
        },
        :container_expected => {
          Time.at(1_446_500_000).utc => {
            "cpu_usage_rate_average"     => 10.0,
            "mem_usage_absolute_average" => 50.0
          }
        }
      },
      {
        :counters           => [
          {
            :args => 'cpu/usage',
            :data => [
              {'start' => 1_446_499_940_000, 'end' => 1_446_500_000_000, 'min' => 0},
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 12_000_000_000}
            ]
          },
          {
            :args => 'network/tx',
            :data => [
              {'start' => 1_446_499_940_000, 'end' => 1_446_500_000_000, 'min' => 0},
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 460_800}
            ]
          },
          {
            :args => 'network/rx',
            :data => [
              {'start' => 1_446_499_940_000, 'end' => 1_446_500_000_000, 'min' => 0},
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 153_600}
            ]
          }
        ],
        :gauges             => [
          {
            :args => 'memory/usage',
            :data => [
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 1_073_741_824}
            ]
          }
        ],
        :node_expected      => {},
        :container_expected => {}
      }
    ]

    it "node counters and gauges are correctly processed" do
      METRICS_EXERCISES.each do |exercise|
        exercise[:counters].each do |metrics|
          allow_any_instance_of(described_class::HawkularLegacyCaptureContext)
            .to receive(:fetch_counters_data)
            .with("machine/node/#{metrics[:args]}")
            .and_return(metrics[:data])
        end

        exercise[:gauges].each do |metrics|
          allow_any_instance_of(described_class::HawkularLegacyCaptureContext)
            .to receive(:fetch_gauges_data)
            .with("machine/node/#{metrics[:args]}")
            .and_return(metrics[:data])
        end

        _, values_by_ts = @node.perf_collect_metrics('realtime')

        expect(values_by_ts['target']).to eq(exercise[:node_expected])
      end
    end

    it "container counters and gauges are correctly processed" do
      METRICS_EXERCISES.each do |exercise|
        exercise[:counters].each do |metrics|
          allow_any_instance_of(described_class::HawkularLegacyCaptureContext)
            .to receive(:fetch_counters_data)
            .with("container/group/#{metrics[:args]}")
            .and_return(metrics[:data])
        end

        exercise[:gauges].each do |metrics|
          allow_any_instance_of(described_class::HawkularLegacyCaptureContext)
            .to receive(:fetch_gauges_data)
            .with("container/group/#{metrics[:args]}")
            .and_return(metrics[:data])
        end

        _, values_by_ts = @container.perf_collect_metrics('realtime')

        expect(values_by_ts['target']).to eq(exercise[:container_expected])
      end
    end
  end
end
