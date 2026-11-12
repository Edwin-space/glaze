/* Bounded scroll timeline: no scroll hijacking, timers or synthetic input. */
(() => {
  const root = document.querySelector('.device-journey');
  if (!root) return;
  const stage = root.querySelector('.journey-stage');
  const stories = [...root.querySelectorAll('[data-story]')];
  const screens = [...root.querySelectorAll('[data-screen-step]')];
  const jumps = [...root.querySelectorAll('[data-jump]')];
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  let current = -1;
  let pending = false;
  const update = () => {
    pending = false;
    if (reduce.matches) return;
    const distance = Math.max(1, root.offsetHeight - innerHeight);
    const progress = Math.min(1, Math.max(0, -root.getBoundingClientRect().top / distance));
    const index = Math.min(stories.length - 1, Math.floor(progress * stories.length));
    stage.style.setProperty('--journey-progress', String(progress));
    stage.style.setProperty('--beat', String((progress * stories.length) % 1));
    if (index === current) return;
    current = index;
    stage.dataset.step = String(index);
    stories.forEach((node, i) => {
      const active = i === index;
      node.classList.toggle('is-active', active);
      node.setAttribute('aria-hidden', String(!active));
      node.inert = !active;
    });
    screens.forEach((node, i) => {
      const active = index < 4 && i === index;
      node.classList.toggle('is-active', active);
      node.setAttribute('aria-hidden', String(!active));
    });
    root.querySelector('.journey-mac').setAttribute('aria-hidden', String(index > 3));
    root.querySelector('.journey-phone').setAttribute('aria-hidden', String(index !== 4 && index !== 5));
    root.querySelector('.journey-tv').setAttribute('aria-hidden', String(index !== 6));
    root.querySelector('.workflow-overlay').setAttribute('aria-hidden', String(index !== 1 && index !== 2));
    root.querySelector('.sidecar-files').setAttribute('aria-hidden', String(index !== 3));
    jumps.forEach((node, i) => {
      if (i === index) node.setAttribute('aria-current', 'step');
      else node.removeAttribute('aria-current');
    });
    root.querySelector('.journey-current').textContent = `${String(index + 1).padStart(2, '0')} / 07`;
  };
  const request = () => {
    if (pending) return;
    pending = true;
    requestAnimationFrame(update);
  };
  const configure = () => {
    document.documentElement.classList.toggle('motion-ready', !reduce.matches);
    if (reduce.matches) {
      stories.forEach(node => { node.inert = false; node.removeAttribute('aria-hidden'); });
      root.querySelectorAll('[aria-hidden]').forEach(node => node.removeAttribute('aria-hidden'));
    }
    current = -1;
    request();
  };
  jumps.forEach(button => button.addEventListener('click', () => {
    const index = Number(button.dataset.jump);
    const top = root.getBoundingClientRect().top + scrollY;
    const distance = Math.max(1, root.offsetHeight - innerHeight);
    const target = top + distance * (index + .1) / stories.length;
    window.scrollTo({top:target, behavior:reduce.matches ? 'instant' : 'smooth'});
  }));
  root.querySelectorAll('[data-language]').forEach(button => button.addEventListener('click', () => {
    const translated = button.dataset.language === 'translated';
    root.querySelectorAll('[data-language]').forEach(node => node.setAttribute('aria-pressed', String(node === button)));
    root.querySelector('.subtitle-example').textContent = translated ? '이야기는 당신 곁에 남습니다.' : 'A story stays with you.';
    root.querySelector('.language-explanation').textContent = translated
      ? '영어 음성 → 영문 자막 → 사용자 언어로 번역. 한국어 환경을 예로 보여줍니다.'
      : '영어 음성 → 영문 자막. 원어 표현을 그대로 읽으며 학습합니다.';
  }));
  addEventListener('scroll', request, {passive:true});
  addEventListener('resize', request, {passive:true});
  reduce.addEventListener('change', configure);
  configure();
})();
