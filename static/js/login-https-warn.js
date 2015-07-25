(function() {
  'use strict';
  if (window.location.protocol !== 'https:') {
    $('.alert-https').removeClass('hidden');
  }
})();
