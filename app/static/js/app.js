'use strict';
document.querySelectorAll('form[data-submit-once]').forEach(form => {
  form.querySelectorAll('button[type="submit"]').forEach(button => {
    button.dataset.label = button.textContent;
  });
  form.addEventListener('submit', () => {
    form.querySelectorAll('button[type="submit"]').forEach(button => {
      button.disabled = true;
      button.textContent = '正在处理，请稍候…';
    });
  });
});
document.querySelectorAll('[data-print]').forEach(button => {
  button.addEventListener('click', () => window.print());
});
window.addEventListener('pageshow', () => {
  document.querySelectorAll('form[data-submit-once] button[type="submit"]').forEach(button => {
    button.disabled = false;
    button.textContent = button.dataset.label;
  });
});
