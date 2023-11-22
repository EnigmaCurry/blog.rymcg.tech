/* global clipboard */
/* eslint-disable no-console */
/* Copyright (c) 2019 Danny Guo */
/* https://www.dannyguo.com/blog/how-to-add-copy-to-clipboard-buttons-to-code-blocks-in-hugo/ */

function addCopyButtons(clipboard) {
  document.querySelectorAll('pre > code').forEach(function(codeBlock) {
    var lang = codeBlock.getAttribute('data-lang');
    var header = document.createElement('div');
    header.classList.add("code-header");
    var button = document.createElement('button');
    button.className = 'copy-code-button';
    button.type = 'button';
    button.innerText = 'Copy';
    var title = document.createElement('div');
    title.classList.add('title');
    if (lang === 'env') {
      header.classList.add('lang-env');
      title.innerText=" $> # Customize temporary variables";
    } else if (lang === 'env-static') {
      header.classList.add('lang-env-static');
      title.innerText=" # Set permanent environment in ~/.bashrc or ~/.bash_profile";
    } else if (lang === 'bash') {
      header.classList.add('lang-bash');
      title.innerText=" $> # Run in Bash shell";
    } 

    header.appendChild(title);
    header.appendChild(button);

    button.addEventListener('click', function() {
      clipboard.writeText(codeBlock.textContent).then(
        function() {
          /* Chrome doesn't seem to blur automatically, leaving the button
             in a focused state */
          button.blur();
          button.innerText = 'Copied!';
          setTimeout(function() {
            button.innerText = 'Copy';
          }, 2000);
        },
        function(error) {
          button.innerText = 'Error';
          console.error(error);
        }
      );
    });

    var pre = codeBlock.parentNode;
    if (pre.parentNode.classList.contains('highlight')) {
      var highlight = pre.parentNode;
      highlight.parentNode.insertBefore(header, highlight);
    } else {
      pre.parentNode.insertBefore(header, pre);
    }
    pre.style.backgroundColor = "#000";
  });
}

if (navigator && navigator.clipboard) {
    addCopyButtons(navigator.clipboard);
} else {
    var script = document.createElement('script');
    script.src =
        'https://cdnjs.cloudflare.com/ajax/libs/clipboard-polyfill/2.7.0/clipboard-polyfill.promise.js';
    script.integrity = 'sha256-waClS2re9NUbXRsryKoof+F9qc1gjjIhc2eT7ZbIv94=';
    script.crossOrigin = 'anonymous';

    script.onload = function() {
        addCopyButtons(clipboard);
    };

    document.body.appendChild(script);
}
