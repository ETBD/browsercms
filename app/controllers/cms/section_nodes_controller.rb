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
      node_to_move = SectionNode.find(params[:id])
      position = params[:position].try(:to_i)

      # The parent folder/section of the node's previous location
      previous_parent = node_to_move.parent

      # The parent folder/section of the node's new, target location
      target_parent = SectionNode.find(params[:target_node_id])

      # If position is not present, move item to the end of the list
      if position.present?
        node_to_move.move_to(target_parent.node, position)
      else
        node_to_move.move_to_end(target_parent.node)
      end

      # Return success. Include all nodes that will need their position and depth updated on the frontend.
      render json: {
        success: true,
        message: %(
          '#{node_to_move.node.name}' was moved to position ##{position} in '#{target_parent.node.name}' folder.
        ).squish,
        updated_values: nodes_to_update_on_success(previous_parent, target_parent)
      }
    rescue StandardError => e
      render json: {
        success: false,
        error: e.message,
        message: %(
          Failed to move '#{node_to_move.node.name}' to position ##{position} in '#{target_parent.node.name}' folder.
        ).squish
      }, status: 500
    end

    def repair_sitemap
      SectionNode.repair_sitemap
      flash[:notice] = 'Repairing sitemap positions. Please refresh in a moment or two to see the results.'
      redirect_to sitemap_path
    end

    private

    # Retrieves all siblings that will need updating on success. This includes all siblings
    # from the node's previous location as well as siblings from the node's new/target location. Also
    # includes the node itself.
    #
    # The dedupe is deliberately OUTSIDE the union and keyed on id. It used to be
    # `.distinct` on the second relation, inside the parens, where it was a SELECT
    # DISTINCT over rows that were already distinct and could not see across the two
    # halves -- and duplicates between the halves are the only kind this method
    # produces. It produces them on every move within a single folder, because
    # previous_parent and target_parent are then the same record and both queries
    # return the same siblings.
    #
    # Fixed in Phase 4 stage I, after reading the consumer:
    # Sitemap.prototype.updateValuesOnSuccess (cms/sitemap.js:188) only assigns, so the
    # duplicate was cosmetic and the change is safe. Covered by
    # test/functional/cms/section_nodes_controller_test.rb, in both directions -- one
    # test fails if duplicates come back, another if the union stops including the
    # previous parent's siblings.
    def nodes_to_update_on_success(previous_parent, target_parent)
      siblings = previous_parent.children.not_of_type(Cms::Section::HIDDEN_NODE_TYPES) +
                 target_parent.children.not_of_type(Cms::Section::HIDDEN_NODE_TYPES)
      siblings.uniq(&:id).map { |n| [n.id, n.position, n.depth] }
    end
  end
end
