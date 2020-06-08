//= require 'jquery'
//= require 'jquery-ui'
//= require 'jquery.cookie'
//= require 'bootstrap'
//= require 'cms/ajax'
//= require 'underscore'
//= require 'cms/new_content_button'

// Sitemap uses JQuery.Draggable/Droppable to handling moving elements, with custom code below.
// Open/Close are handled as code below.
var Sitemap = function () {
};

// Name of cookie that stores SectionNode ids that should be opened.
Sitemap.STATE = 'cms.sitemap.open_folders';

Sitemap.prototype.select = function (selectedRow) {
  $('.nav-list-span').removeClass('active');
  selectedRow.addClass('active');
  newContentButton.updateButtons(selectedRow);
};

// Different Content types have different behaviors when double clicked.
Sitemap.prototype._doubleClick = function (event) {
  var type = $(event.target).data('type');
  switch (type) {
    case 'section':
    case 'link':
      $('#properties-button')[0].click();
      break;
    default:
      $('#edit-button')[0].click();
  }
};

// @param [Number] node_id
// @param [Number] target_node_id
// @param [Number] position A 1 based position for order
Sitemap.prototype.moveTo = function (node_id, target_node_id, position) {
  var path = "/cms/section_nodes/" + node_id + '/move_to_position'
  $.cms_ajax.put({
    url: path,
    data: {
      target_node_id: target_node_id,
      position: position
    },
    success: function (result) {
      //console.log(result);
    }
  });
};

// @param [Selector] Determines if a section is open.
Sitemap.prototype.isOpen = function (row) {
  return row.find('.type-icon').hasClass('icon-folder-open');
};

// @param [Selector] link A selected link (<a>)
// @param [String] icon The full name of the icon (icon-folder-open)
Sitemap.prototype.changeIcon = function (row, icon) {
  row.find('.type-icon').attr('class', 'type-icon').addClass(icon);
};

// @param [Number] id
Sitemap.prototype.saveAsOpened = function (id) {
  $.cookieSet.add(Sitemap.STATE, id);
};

// @param [Number] id
Sitemap.prototype.saveAsClosed = function (id) {
  $.cookieSet.remove(Sitemap.STATE, id);
};

// Reopen all sections that the user was last working with.
Sitemap.prototype.restoreOpenState = function () {
  var section_node_ids = $.cookieSet.get(Sitemap.STATE);
  _.each(section_node_ids, function (id) {
    if (id !== '') {
      var row = $('.nav-list-span[data-id=' + id + ']');
      sitemap.open(row, {animate: false});
    }
  });
};

// Determines if the selected row is a Folder or not.
Sitemap.prototype.isFolder = function (row) {
  return row.data('type') == 'folder';
};

Sitemap.prototype.isClosable = function (row) {
  return row.data('closable') == true;
};

// @param [Selector] link
// @param [Object] options
Sitemap.prototype.open = function (row, options) {
  options = options || {}
  _.defaults(options, {animate: true});
  this.changeIcon(row, 'icon-folder-open');
  var siblings = row.siblings('.children');
  if (options.animate) {
    siblings.slideToggle('fast');
  }
  else {
    siblings.show();
  }
  this.saveAsOpened(row.data('id'));
};

// Attempts to open the given row. Will skip if the item cannot or is already open.
Sitemap.prototype.attemptOpen = function (row, options) {
  if (this.isClosable(row) && !this.isOpen(row)) {
    this.open(row, options);
  }
};

Sitemap.prototype.close = function (row) {
  this.changeIcon(row, 'icon-folder');
  row.siblings('.children').slideToggle('fast');
  this.saveAsClosed(row.data('id'));
};

Sitemap.prototype.toggleOpen = function (row) {
  if (!this.isClosable(row)) {
    return;
  }
  if (this.isOpen(row)) {
    this.close(row);
  } else {
    this.open(row);
  }
};

Sitemap.prototype.updateDepth = function (element, newDepth) {
  var depthClass = "level-" + newDepth;
  element.attr('class', 'ui-draggable ui-droppable nav-list-span').addClass(depthClass);
  element.attr('data-depth', newDepth);
};

var sitemap = new Sitemap();

// Enable dragging of items around the sitemap.
jQuery(function ($) {
  if ($('#sitemap').exists()) {

    $('#sitemap .draggable').draggable({
      containment: '#sitemap',
      revert: true,
      revertDuration: 0,
      axis: 'y',
      delay: 250,
      cursor: 'move',
      stack: '.nav-list-span',
      scroll: false
    });

    $('#sitemap .nav-list-span').droppable({
      hoverClass: "droppable",
      drop: function (event, ui) {
        // The target is where the draggable is being dropped.
        var $target = $(this);
        var $draggable = ui.draggable;

        var sourceElement = $draggable.closest('.nav-list');
        var destinationElement = $target.closest('.nav-list');
        // var sourceDepth = $(sourceElement).find("[data-depth]").data('depth');
        var destinationDepth = $target.data('depth');
        // var sourceParentId = sourceElement.parents('.nav-list:first').find('.nav-list-span:first').data('id');
        var destinationParentId = destinationElement.parents('.nav-list:first').find('.nav-list-span:first').data('id');
        var newParentId;

        // Handle whether the item is dropped onto a folder or not.
        if (sitemap.isFolder($target)) {
          // Determine whether the intention is to move the item into the folder, or merely to reorder.
          if ($target.hasClass('move-into-folder')) {
            console.log('move into folder');
            moveIntoFolder();
          } else if ($target.find('.icon-folder-open').length > 0) {
            console.log('forced reorder to first');
            reorderItem(1);
          } else {
            console.log('reorder next to folder');
            reorderItem();
          }
        } else {
          console.log('default reorder');
          reorderItem();
        }

        // Handle when a folder is dropped onto another folder
        // if (sitemap.isFolder($target) && sitemap.isFolder($draggable)) {
        //   // If the draggable has been held above the target for long enough to get the
        //   // .folder-into-folder class, move it into the folder. Otherwise, treat the action as
        //   // a simple reorder.
        //   if ($target.hasClass('move-into-folder')) {
        //     console.log('move folder into folder');
        //     moveIntoFolder();
        //   } else {
        //     console.log('reorder folder');
        //     reorderItem();
        //   }
        // // Handle when a file is dropped onto a folder
        // } else if (sitemap.isFolder($target) && $target.hasClass('move-into-folder')) {
        //   console.log('move file into folder');
        //   moveIntoFolder();
        // // Handle when a file is dropped at the top of an open folder
        // } else if (sitemap.isFolder($target) && $target.find('.icon-folder-open').length > 0) {
        //   console.log('reorder first');
        //   // Force the item into the top position
        //   reorderItem(1);
        // // All other actions are simply reorders
        // } else {
        //   console.log('default reorder');
        //   // Drop INTO page
        //   reorderItem();
        // }

        // Remove any movement classes that may remain.
        $('.move-into-folder').removeClass('move-into-folder');

        function reorderItem(position) {
          console.log('Forced Position: ' + position);
          sitemap.updateDepth($draggable, destinationDepth);
          sourceElement.insertAfter(destinationElement);
          newParentId = destinationParentId;
          moveItemOnServer(position);
        }

        function moveIntoFolder() {
          sitemap.attemptOpen($target);
          sitemap.updateDepth($draggable, destinationDepth + 1);
          destinationElement.find('li').first().append(sourceElement);
          newParentId = $(destinationElement).find('.nav-list-span:first').data('id');
          moveItemOnServer();
        }

        function moveItemOnServer(position) {
          var nodeIdToMove = $draggable.data('id');
          // var newPosition = sourceElement.index();
          var newPosition = (position === undefined) ? sourceElement.index() : position;
          console.log('Moving ' + nodeIdToMove + ' to ' + newParentId + ', pos: ' + newPosition);
          sitemap.moveTo(nodeIdToMove, newParentId, newPosition);

          // debugger;

          // Need a manual delay otherwise the animation happens before the insert.
          window.setTimeout(function () {
            ui.draggable.effect({effect: 'highlight', duration: 2000, color: '#d9fccc'});
          }, 200);
        }
      },
      out: function (event, ui) {
        $(this).removeClass('move-into-folder');
      },
      over: function (event, ui) {
        var $target = $(this);

        // If hovering over a folder, attempt to determine intntion by pausing.
        if (sitemap.isFolder($target)) {
          window.setTimeout(function () {
            // If still hovering over the holder when this timeout fires, set a new class and allow
            // dropping into the folder.
            if ($target.hasClass('droppable')) {
              $target.addClass('move-into-folder');
            }
          }, 1100);
        }
      }
    });
  }
});

// Open/close folders when rows are clicked.
jQuery(function ($) {
  // Ensure this only loads on sitemap page.
  if ($('#sitemap').exists()) {
    sitemap.restoreOpenState();
    $('.nav-list-span').on('click', function (event) {
      sitemap.toggleOpen($(this));
      sitemap.select($(this));
    });
  }

});

// Make Sitemap filters show specific content types.
jQuery(function ($) {
  $('#sitemap li[data-nodetype]').hide();
  $('#filtershow').change(function () {
    $('#sitemap li[data-nodetype]').slideUp();
    var what = $(this).val();
    if (what == "none") {
      $('#sitemap li[data-nodetype]').slideUp();
    } else if (what == "all") {
      $('#sitemap li[data-nodetype]').slideDown();
      $('#sitemap li[data-nodetype]').parents('li').children('a[data-toggle]').click();
    } else {
      $('#sitemap li[data-nodetype="' + what + '"]').slideDown();
      $('#sitemap li[data-nodetype="' + what + '"]').parents('li').children('a[data-toggle]').click();
    }
  });
});
