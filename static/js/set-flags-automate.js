(function() {
  'use strict';
  $('.flag-tick').click(function(evt) {
    var evtFlag = Number(evt.target.getAttribute('data-flag'));
    var currFlags = $('#flags').val();
    if (!isNaN(evtFlag)) {
      if (evt.target.checked) {
        currFlags |= evtFlag;
      } else {
        currFlags &= ~evtFlag;
      }

      $('#flags').val(currFlags);
    }
  });
})();