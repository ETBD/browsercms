module Cms
  class SitemapSweeper < ActionController::Caching::Sweeper
    observe Cms::Section
    observe Cms::Page

    # If our sweeper detects that a Product was created call this
    def after_create( node )
      expire_cache_for( node.path )
    end

    # If our sweeper detects that a Product was updated call this
    def after_update( node )
      expire_cache_for( node.path )
    end

    # If our sweeper detects that a Product was deleted call this
    def after_destroy( node )
      expire_cache_for( node.path )
    end

    private
    def expire_cache_for( path )
      # get the list of user names that has been used in the cache
      # sitemap cache is per user, so it needs to be deleted for each user
      cache_users = Rails.cache.read( "cache_fragment_sitemap_users" ) || Set.new

      # Expire a fragment
      path_bits = path.split( '/' )
      path_bits.shift

      # the first / in the path is special, denoting the root
      # so we have to expire it manually
      cache_users.each do |user|
        expire_fragment( "cache_fragment_sitemap_#{user}_/" )
      end

      # loop through the array of path segments,
      # accumulating a running path
      # and clear the cache for it
      path_bits.inject( '' ) { |path_accm, path_bit|
        path_accm += "/#{path_bit}"

        cache_users.each do |user|
          expire_fragment( "cache_fragment_sitemap_#{user}_#{path_accm}" )
        end

        path_accm
      }
    end
  end
end
