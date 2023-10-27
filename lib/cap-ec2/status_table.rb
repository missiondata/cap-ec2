module CapEC2
  class StatusTable
    include CapEC2::Utils

    def initialize(instances)
      @instances = instances
      output
    end

    def header_row
      %w[
        Num
        Name
        ID
        Type
        DNS
        Zone
        Roles
        Stages
      ]
    end

    def output
      table = Terminal::Table.new(
        style: {
          border_x: '',
          border_i: '',
          border_y: ''
        }
      )
      table.add_row header_row
      @instances.each_with_index do |instance, index|
        table.add_row instance_to_row(instance, index)
      end
      puts table
    end

    def instance_to_row(instance, index)
      [
        format('%02d:', index),
        tag_value(instance, 'Name') || '',
        instance.instance_id,
        instance.instance_type,
        CapEC2::Utils.contact_point(instance),
        instance.placement.availability_zone,
        tag_value(instance, roles_tag),
        tag_value(instance, stages_tag)
      ]
    end
  end
end
