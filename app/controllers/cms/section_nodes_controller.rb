module Cms
  class SectionNodesController < Cms::BaseController
    include SectionNodesHelper

    check_permissions :publish_content, :except => [:index]

    def index
      @modifiable_sections = current_user.modifiable_sections
      @sitemap_editable = current_user_can_modify(@modifiable_sections, SectionNode.first, nil)

      # Serializes all necessary pages, links, and sections starting with the Home folder.
      @sitemap = Section.sitemap.first

      render 'show'
    end

    def slow_index
      @modifiable_sections = current_user.modifiable_sections
      @public_sections = Group.guest.sections.to_a # Load once here so that every section doesn't need to.

      @sitemap = Section.sitemap
      @root_section_node = @sitemap.keys.first
      @section = @root_section_node.node
      render 'slow_show'
    end

    def move_to_position
      @source_node = SectionNode.find(params[:id])
      target_node = SectionNode.find(params[:target_node_id])
      source_node = @source_node.section
      position = params[:position].try(:to_i)

      # If position is not present, move item to the end of the list
      if position.present?
        @source_node.move_to(target_node.node, position)
      else
        @source_node.move_to_end(target_node.node)
      end

      render json: {
        success: true,
        message: %(
          '#{@source_node.node.name}' was moved to position ##{position} in '#{target_node.node.name}' folder.
        ).squish,
        updated_positions: updated_positions(@source_node, target_node)
      }
    rescue StandardError => e
      render json: {
        success: false,
        error: e.message,
        message: %(
          Failed to move '#{@source_node.node.name}' to position ##{position} in '#{target_node.node.name}' folder.
        ).squish
      }, status: 500
    end

    private

    # Retrieve new positions from all related nodes so that the front-end can be updated.
    def updated_positions(source_node, target_node)
      source_node.siblings.not_of_type(Cms::Section::HIDDEN_NODE_TYPES).pluck(:id, :position) +
      target_node.siblings.not_of_type(Cms::Section::HIDDEN_NODE_TYPES).pluck(:id, :position)
    end
  end
end
