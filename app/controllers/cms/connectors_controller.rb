module Cms
class ConnectorsController < Cms::BaseController
  
  before_filter :load_page, :only => [:new, :create]
  
  def new    
    @block_type = ContentType.find_by_key(params[:block_type] || session[:last_block_type] || 'html_block')
    @container = params[:container]
    @connector = @page.connectors.build(:container => @container)
    @blocks = @block_type.model_class.where(["deleted = ?", false]).order("name")
  end

  def create
    @block_type = ContentType.find_by_key(params[:connectable_type])
    raise "Unknown block type" unless @block_type
    @block = @block_type.model_class.find(params[:connectable_id])
    if @page.create_connector(@block, params[:container])
      redirect_to @page.path
    else
      @blocks = @block_type.model_class.all(:order => "name")      
      render :action => 'new'
    end
  end
  
  def destroy
    @connector = Connector.find(params[:id])
    @page = @connector.page.as_of_draft_version
    @connectable = @connector.connectable
    if @page.remove_connector(@connector)
      flash[:notice] = "Removed '#{@connectable.name}' from the '#{@connector.container}' container"
    else
      flash[:error] = "Failed to remove '#{@connectable.name}' from the '#{@connector.container}' container"
    end
    respond_to do |format|
      format.html { redirect_to @page.path  }
      format.json { render :json => @connector }
    end
  end

  { #Define actions for moving connectors around
    :up => "up in",
    :down => "down in",
    :to_top => "to the top of",
    :to_bottom => "to the bottom of"    
  }.each do |move, where|
    define_method "move_#{move}" do
      @connector = Connector.find(params[:id])
      @page = @connector.page
      @connectable = @connector.connectable
      if @page.send("move_connector_#{move}", @connector)
        flash[:notice] = "Moved '#{@connectable.name}' #{where} the '#{@connector.container}' container"
      else
        # TODO: Display Correct Flash Notice: Both success and
        # error are being called and method is displaying
        # the 'Failed' message when the change actually succeeds.
        # flash[:error] = "Failed to move '#{@connectable.name}' #{where} the '#{@connector.container}' container"
      end

      respond_to do |format|
        format.html { redirect_to @page.path  }
        format.json { render :json => @connector }
      end

    end
  end

  private
    def load_page
      @page = Page.find(params[:page_id]).as_of_draft_version
    end

end
end
