namespace :sitemap do
  desc 'clean up and repair section node positioning'
  task repair: :environment do
    # Cms::Attachment nodes should always have a position of NULL
    clear_attachment_positions

    # Positions should be unique within a section. Loop through all roots (currently only one) and
    # recursively repair the positions of any children.
    Cms::SectionNode.roots.each do |root_node|
      puts "[POS][REPAIR] Looking at #{Cms::Section.count} sections for positions needing repair..."
      @updated = 0
      repair_section_node_positions(root_node)
      puts "Done. #{@updated} section nodes updated."
    end
  end

  def clear_attachment_positions
    attachment_nodes = Cms::SectionNode.where(node_type: 'Cms::Attachment').where.not(position: nil)
    puts "[POS][REPAIR] Setting position to NULL for #{attachment_nodes.size} attachment(s)..."
    attachment_nodes.update_all(position: nil)
    puts 'Done'
  end

  def repair_section_node_positions(node)
    # Find all positionable children within this node
    children = node.children.not_of_type('Cms::Attachment')
    puts "[POS][REPAIR]#{'  ' * node.depth}   Processing #{children.count} children for SectionNode ##{node.id} (#{node.node.name})..." if debug?

    # Sort by current position and item name, then update child positions, starting with 0.
    # Only update nodes where the position needs to change.
    children.sort_by { |child| [child.position, child.node.name] }.each_with_index do |child, i|
      next if child.position == i

      puts "[POS][REPAIR]#{'  ' * child.depth} -> Updating postion from #{child.position} to #{i} for SectionNode ##{child.id} (#{child.node.name})" if debug?
      child.update_column(:position, i)
      @updated += 1
    end

    # Continue into any child sections
    children.where(node_type: 'Cms::Section').each do |child_node|
      repair_section_node_positions(child_node)
    end
  end

  def debug?
    ENV['LOG_LEVEL'] == 'debug'
  end
end
