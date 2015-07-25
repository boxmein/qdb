window.addEventListener('load', $.material.init.bind($.material)); 
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
      try { 
        var obj = JSON.parse(data); 
        $that.html('&and; ' + obj.votes_now);
        $that.addClass('voted');
      } catch (err) {
        console.error(err);
        $that.html('&and; err');
        $that.addClass('error');
      }
    });
  });
});
