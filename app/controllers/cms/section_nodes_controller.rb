module Cms
  class SectionNodesController < Cms::BaseController

    check_permissions :publish_content, :except => [:index]

    def index
      @modifiable_sections = current_user.modifiable_sections
      @public_sections = Group.guest.sections.to_a # Load once here so that every section doesn't need to.

      @sitemap = Section.sitemap
      @root_section_node = @sitemap.keys.first
      @section = @root_section_node.node
      render 'show'
    end

    def move_to_position
      @section_node = SectionNode.find(params[:id])
      target_node = SectionNode.find(params[:target_node_id])
      source_node = @section_node.section
      position = params[:position].try(:to_i)

      ap "*" * 50
      ap position
      ap "*" * 50
      # If position is not present, move item to the end of the list
      if position.present?
        @section_node.move_to(target_node.node, position)
      else
        ap "*" * 50
        ap 'Moving to end!'
        ap "*" * 50
        @section_node.move_to_end(target_node.node)
      end

      @section_node.node.touch
      target_node.node.touch_self_and_ancestors
      source_node.touch_self_and_ancestors

      render json: {
        success: true,
        message: %(
          '#{@section_node.node.name}' was moved to position ##{position} in '#{target_node.node.name}'
        )
      }
    rescue StandardError => e
      render json: {
        success: false,
        message: %(
          Failed to move #{@section_node.node.name}' to position ##{position} in '#{target_node.node.name}'
          Error: #{e}
        )
      }
    end
  end
end
