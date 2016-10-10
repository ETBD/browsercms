module Cms
  class ImageBlocksController < Cms::ContentBlockController
    def image_block_params
      params.permit(:location_ids)
    end
  end
end
