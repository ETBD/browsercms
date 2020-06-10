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
// @param [Number] position A 0-based position for order
Sitemap.prototype.moveTo = function ($draggable, targetNodeId, position) {
  var nodeId = $draggable.data('id');
  var path = "/cms/section_nodes/" + nodeId + '/move_to_position'

  console.log('Moving ' + nodeId + ' to ' + targetNodeId + ', pos: ' + position);

  $.cms_ajax.put({
    url: path,
    data: {
      target_node_id: targetNodeId,
      position: position
    },
    success: function (result) {
      console.log(result);

      // Set the position attrribute to the  new position. Also update the DOM as well, so it's
      // visible in the inspector
      $draggable.data('position', position);
      $draggable[0].dataset.position = position;

      // Need a manual delay otherwise the animation happens before the insert.
      window.setTimeout(function () {
        $draggable.effect({effect: 'highlight', duration: 2000, color: '#d9fccc'});
      }, 200);
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
  // this.changeIcon(row, 'icon-folder-open');
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

Sitemap.prototype.updateDepth = function ($element, newDepth) {
  var depthClass = "level-" + newDepth;
  $element.attr('class', 'ui-draggable ui-droppable nav-list-span').addClass(depthClass);
  $element.attr('data-depth', newDepth);
  console.log('Updating parent depth ' + newDepth);

  this.updateChildDepth($element, newDepth + 1)
};

// Recursively updates the depth of all children within the given element.
Sitemap.prototype.updateChildDepth = function ($element, newDepth) {
  var $children = $element.closest('.nav-list-item').find('.children .nav-list-span');
  var that = this;

  if ($children.length > 0) {
    // console.log('Updating children');
    $children.each(function() {
      var $element = $(this);

      // console.log('Updating child depth ' + newDepth);
      $element.attr('class', 'ui-draggable ui-droppable nav-list-span').addClass("level-" + newDepth);
      $element.attr('data-depth', newDepth);
      that.updateChildDepth($element, newDepth + 1)
    });
  }
};

// Move an item to the top position within a folder.
// The $target is the folder itself, so the depth needs to be 1 deeper.
// The new position will be 1 (first) in the 1-indexed list.
Sitemap.prototype.moveToTopOfFolder = function ($source, $target, $sourceRow, $targetRow) {
  // The new folder is the target folder itself.
  var newFolderId = $target.closest('.nav-folder').find('.nav-list-span:first').data('id');
  var newDepth = $target.data('depth') + 1;

  this.updateDepth($source, newDepth);
  $sourceRow.prependTo($targetRow.find('.children:first'));
  this.moveTo($source, newFolderId, 1);
}

// Move an item to the spot immediately after a folder, on the same level.
// The $target is the folder itself, so the depth should be the same
// The new position will be 1 greater than the target.
Sitemap.prototype.moveAfterFolder = function ($source, $target, $sourceRow, $targetRow) {
  // The new folder is the PARENT folder of the target folder.
  var newFolderId = $($target.parents('.nav-folder')[1]).find('.nav-list-span:first').data('id');
  var newDepth = $target.data('depth');
  var newPosition = $target.data('position') + 1;

  this.updateDepth($source, newDepth);
  $targetRow.find('li').first().append($sourceRow);
  this.moveTo($source, newFolderId, newPosition);
}

// Move an item to the spot immediately after another item, on the same level.
// The $target is an item, so the depth should be the same
// The new position will be 1 greater than the target.
Sitemap.prototype.moveAfterItem = function ($source, $target, $sourceRow, $targetRow) {
  // The new folder is the PARENT folder of the target item.
  var newFolderId = $target.closest('.nav-folder').find('.nav-list-span:first').data('id');
  var newDepth = $target.data('depth');
  var newPosition = $target.data('position') + 1;

  this.updateDepth($source, newDepth);
  $sourceRow.insertAfter($targetRow);
  this.moveTo($source, newFolderId, newPosition);
}

var sitemap = new Sitemap();

// Enable dragging of items around the sitemap.
jQuery(function ($) {
  if ($('#sitemap').exists()) {

    $('#sitemap .draggable').draggable({
      // addClasses: false, // possible performance improvement
      axis: 'y',
      containment: '#sitemap',
      cursor: 'move',
      delay: 250,
      opacity: .8,
      revert: true,
      revertDuration: 0,
      scroll: true,
      stack: '.nav-list-span',
    });

    $('#sitemap .nav-list-span').droppable({
      // addClasses: false, // possible performance improvement
      hoverClass: "droppable",
      drop: function (event, ui) {
        // The '$target' is where the '$source' is being dropped.
        var $target = $(this);
        var $source = ui.draggable;
        var $sourceRow = $source.closest('.nav-list');
        var $targetRow = $target.closest('.nav-list');
        // var $sourceParentId = $source.closest('.nav-folder').find('.nav-list-span:first').data('id');
        // var $targetParentId = $target.closest('.nav-folder').find('.nav-list-span:first').data('id');

        // If dropping on an open folder, put the item at the top.
        if (sitemap.isFolder($target) && sitemap.isOpen($target)) { // && $sourceParentId == $targetParentId) {
          console.log('Moving to top of folder');
          sitemap.moveToTopOfFolder($source, $target, $sourceRow, $targetRow);
        // If the target is a closed folder, put the item immediately after the folder.
        } else if (sitemap.isFolder($target) && !sitemap.isOpen($target)) {
          console.log('Moving after target folder');
          sitemap.moveAfterFolder($source, $target, $sourceRow, $targetRow);
        // Otherwise, put the item immediately after the target item.
        } else {
          console.log('Moving after target item');
          sitemap.moveAfterItem($source, $target, $sourceRow, $targetRow);
        }
      },
      // ABANDONED EXPERIMENT: Attempts to open a closed folder if hovered on for a set amount of time.
      // In practice, however, the folder would open, but the children were not droppable.
      // over: function (event, ui) {
      //   var $target = $(this);
      //
      //   // If hovering over a closed folder for a set amount of time, attempt to open the folder.
      //   if (sitemap.isFolder($target) && !sitemap.isOpen($target)) {
      //     window.setTimeout(function () {
      //       if ($target.hasClass('ui-droppable-hover')) {
      //         sitemap.attemptOpen($target);
      //       }
      //     }, 1100);
      //   }
      // }
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
