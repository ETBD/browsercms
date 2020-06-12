//= require 'cms/namespace'

Cms.NewContentButton = function() {
};

// Setting the 'New Page' path should update the global menu
Cms.NewContentButton.prototype.addPagePath = function(path) {
  $('#new-content-button').attr('href', path);
  $('.add-page-button').attr('href', path);
};

Cms.NewContentButton.prototype.addSectionPath = function(path) {
  $('.add-link-button').attr('href', path);
};

Cms.NewContentButton.prototype.addLinkPath = function(path) {
  $('.add-section-button').attr('href', path);
};

Cms.NewContentButton.prototype.updateButtons = function(selectedElement) {
  var nearestSectionId = selectedElement.closest('.nav-folder').find('.nav-list-span:first').data('node-id');

  this.addPagePath('/cms/sections/' + nearestSectionId + '/pages/new');
  this.addLinkPath('/cms/sections/' + nearestSectionId + '/links/new');
  this.addSectionPath('/cms/sections/new?section_id=' + nearestSectionId);
};

var newContentButton = new Cms.NewContentButton();