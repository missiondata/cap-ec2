# frozen_string_literal: true

RSpec.describe CapEC2::StatusTable do
  let(:instances) do
    data = reservations(
      instance_data('i-1', name: 'web-1', roles: 'web,app', public_dns_name: 'web-1.example.com'),
      instance_data('i-2', name: 'db-1', roles: 'db')
    )
    Aws::EC2::Client.new(region: 'us-east-1', stub_responses: true)
                    .stub_data(:describe_instances, data).reservations.flat_map(&:instances)
  end

  def output_lines
    out = StringIO.new
    $stdout = out
    described_class.new(instances)
    out.string.lines.map(&:strip).reject(&:empty?)
  ensure
    $stdout = STDOUT
  end

  it 'prints a header row' do
    expect(output_lines.first.split).to eq(%w[Num Name ID Type DNS Zone Roles Stages])
  end

  it 'prints one numbered row per instance' do
    rows = output_lines.drop(1).map(&:split)

    expect(rows).to eq(
      [
        %w[00: web-1 i-1 t3.micro web-1.example.com us-east-1a web,app production],
        %w[01: db-1 i-2 t3.micro 10.0.0.1 us-east-1a db production]
      ]
    )
  end
end
