const shots = {
  connection: ['01', ['Один экран.', 'Весь контроль.'], 'Текущая сеть, активный профиль и режим подключения. Закрывай пульт — AutoTurn продолжит работать из верхнего меню.', 'Страница соединения AutoTurn на macOS'],
  routes: ['02', ['Твои сервисы.', 'Твои маршруты.'], 'Выбери сервисы из каталога или добавь свои домены и IP. В режиме по правилам остальные соединения идут напрямую.', 'Страница маршрутов AutoTurn: каталог сервисов и выбранные VPN-направления'],
  settings: ['03', ['Настрой один раз.', 'Пользуйся каждый день.'], 'Домашние сети, автозапуск, разрешения и оформление. Темы пульта, меню и маршрутов можно выбрать независимо.', 'Настройки AutoTurn для macOS']
};
document.querySelectorAll('[data-shot]').forEach(button => {
  button.addEventListener('click', () => {
    const key = button.dataset.shot;
    const [number, title, copy, alt] = shots[key];
    document.querySelectorAll('[data-shot]').forEach(item => {
      item.classList.toggle('selected', item === button);
      item.setAttribute('aria-pressed', String(item === button));
    });
    const img = document.getElementById('gallery-image');
    img.src = `assets/${key}.png`;
    img.alt = alt;
    document.getElementById('shot-number').textContent = `SCREEN / ${number}`;
    const heading = document.getElementById('shot-title');
    heading.replaceChildren(document.createTextNode(title[0]), document.createElement('br'), document.createTextNode(title[1]));
    document.getElementById('shot-copy').textContent = copy;
  });
});
