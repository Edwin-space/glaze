/* Progressive enhancement: the complete story remains readable without JS. */
(() => {
  const tabs = [...document.querySelectorAll('[role="tab"]')];
  const select = (tab, focus = false) => {
    tabs.forEach(item => {
      const active = item === tab;
      item.setAttribute('aria-selected', String(active));
      item.tabIndex = active ? 0 : -1;
      document.getElementById(item.getAttribute('aria-controls')).hidden = !active;
    });
    document.querySelectorAll("[data-mode]").forEach(figure => {
      figure.hidden = figure.dataset.mode !== (tab.id === "read-tab" ? "read" : "watch");
    });
    if (focus) tab.focus();
  };
  document.documentElement.classList.add("tabs-ready");
  if (tabs.length) select(tabs[0]);
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => select(tab));
    tab.addEventListener('keydown', event => {
      let target;
      if (event.key === 'ArrowRight') target = tabs[(index + 1) % tabs.length];
      if (event.key === 'ArrowLeft') target = tabs[(index - 1 + tabs.length) % tabs.length];
      if (event.key === 'Home') target = tabs[0];
      if (event.key === 'End') target = tabs[tabs.length - 1];
      if (!target) return;
      event.preventDefault();
      select(target, true);
    });
  });
  if (!('IntersectionObserver' in window) || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('is-visible');
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.06 });
  document.querySelectorAll('[data-reveal]').forEach(node => observer.observe(node));
  document.documentElement.classList.add('reveal-ready');
})();

// Device mockup controls switch exact captures; generated artwork contains no UI.
(() => {
  const image = document.getElementById('mockup-screen');
  const buttons = [...document.querySelectorAll('[data-screen]')];
  if (!image || !buttons.length) return;
  const screens = {
    subtitles: ['assets/product/mac-subtitles.png', '실제 글레이즈 Mac 앱의 자막 설정 화면'],
    translation: ['assets/product/mac-translation.png', '실제 글레이즈 Mac 앱의 번역 품질과 원문 + 번역 출력 설정'],
    network: ['assets/product/mac-network.png', '실제 글레이즈 Mac 앱의 Synology·WebDAV·DLNA·SMB 연결 안내']
  };
  buttons.forEach(button => button.addEventListener('click', () => {
    const screen = screens[button.dataset.screen];
    if (!screen) return;
    image.src = screen[0];
    image.alt = screen[1];
    buttons.forEach(item => item.setAttribute('aria-pressed', String(item === button)));
  }));
})();
