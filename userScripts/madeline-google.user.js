// ==UserScript==
// @name        Madeline on Google
// @require     http://ajax.googleapis.com/ajax/libs/jquery/1.9.1/jquery.min.js
// @include     http://www.google.com
// @include     http://www.google.com/*
// @include     https://www.google.com
// @include     https://www.google.com/*
// ==/UserScript==

// Append some text to the element with id someText using the jQuery library.
$("body").append('<div class="ben-hi">Hi Maddie!</div>');
$('.ben-hi').css({
  position: 'absolute',
  top: '100px',
  left: '100px',
  'font-size': '60px',
});
