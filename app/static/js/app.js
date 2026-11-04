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
document.querySelectorAll('select[data-goods-category]').forEach(select => {
  const form = select.closest('form');
  const sync = () => {
    form.querySelectorAll('[data-category-group]').forEach(group => {
      const active = group.dataset.categoryGroup === select.value;
      group.hidden = !active;
      group.querySelectorAll('input').forEach(input => {
        input.disabled = !active;
        input.required = active;
      });
    });
  };
  select.addEventListener('change', sync);
  sync();
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
