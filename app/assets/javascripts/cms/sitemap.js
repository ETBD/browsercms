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

Sitemap.prototype.updateChildDepth = function ($element, newDepth) {
  var $children = $element.closest('.nav-list-item').find('.children .nav-list-span');
  var that = this;

  if ($children.length > 0) {
    console.log('Updating children');
    $children.each(function() {
      var $element = $(this);

      console.log('Updating child depth ' + newDepth);
      $element.attr('class', 'ui-draggable ui-droppable nav-list-span').addClass("level-" + newDepth);
      $element.attr('data-depth', newDepth);
      that.updateChildDepth($element, newDepth + 1)
    });
  }
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
        var destinationDepth = $target.data('depth');
        var destinationPosition = $target.data('position');
        var destinationParentId = destinationElement.parents('.nav-list:first').find('.nav-list-span:first').data('id');
        var newParentId = $(destinationElement).find('.nav-list-span:first').data('id');
        var newPosition;

        // debugger

        // Handle whether the item is dropped onto a folder or not.
        if (sitemap.isFolder($target)) {
          // Determine whether the intention is to move the item into the folder, or merely to reorder.
          // If they've hovered long enough to trigger into the folder, put the item there.
          if ($target.hasClass('move-into-folder')) {
            console.log('Action: Move to bottom of folder');
            moveIntoFolder();
          // If the folder is open, assume that they want it at the top of the folder.
          } else if ($target.find('.icon-folder-open').length > 0) {
            console.log('Action: Move to top of folder');
            moveToTopOfFolder();
          // Otherwise, place the item after the folder.
          } else {
            console.log('Action: Place after folder');
            reorderItem();
          }
        // For items NOT dropped into a folder, place the item immediately after the target item.
        } else {
          console.log('Action: Place after item');
          reorderItem();
        }

        // Remove any movement classes that may remain.
        $('.move-into-folder').removeClass('move-into-folder');

        function reorderItem() {
          // Update item and insert into new location (after current item)
          sitemap.updateDepth($draggable, destinationDepth);
          sourceElement.insertAfter(destinationElement);

          // Update the server
          sitemap.moveTo($draggable, destinationParentId, destinationPosition + 1);
        }

        function moveToTopOfFolder() {
          // Update item and insert into new location (at the top of the folder)
          sitemap.updateDepth($draggable, destinationDepth + 1);
          sourceElement.prependTo(destinationElement.find('.children:first'));

          // Update the server
          sitemap.moveTo($draggable, newParentId, 0);
        }

        function moveIntoFolder() {
          // Update item and insert into new location (at the end of the folder)
          sitemap.attemptOpen($target);
          sitemap.updateDepth($draggable, destinationDepth + 1);
          destinationElement.find('li').first().append(sourceElement);

          // Update the server
          sitemap.moveTo($draggable, newParentId);
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
