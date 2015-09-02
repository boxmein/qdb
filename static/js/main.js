window.addEventListener('load', $.material.init.bind($.material)); 
// Upvoting functionality
window.addEventListener('load', function() {
  $('.upvotes').click(function(evt) {
    var $that = $(evt.target);

    var id = $that.parents('.quote').data('id');
    console.log('upvoting id, voted?', id, $that.hasClass('voted'));

    $.ajax({
      url: ($that.hasClass('voted') ? '/unvote/' : '/upvote/') + id,
      method: 'POST'
    })
    .error(console.error.bind(console))
    .done(function(data) {
      try { 
        var obj = JSON.parse(data); 
        $that.html('&and; ' + obj.votes_now);
        $that.toggleClass('voted');
      } catch (err) {
        console.error(err);
        $that.html('&and; err');
        $that.addClass('error');
      }
    });
  });
});
