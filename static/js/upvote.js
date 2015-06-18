// Upvoting functionality
window.addEventListener('load', function() {
  $('.upvotes').click(function(evt) {
    var $that = $(evt.target);

    if ($that.hasClass('.voted')) {
      console.log('already voted!');
      return;
    }

    var id = $that.parents('.quote').data('id');
    console.log('upvoting id', id);

    $.ajax({
      url: '/upvote/' + id,
      method: 'POST'
    })
    .error(console.error.bind(console))
    .done(function(data) {
      $that.html('&and; ' + data);
      $that.addClass('voted');
    });
  });
});
