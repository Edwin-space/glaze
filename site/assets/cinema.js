/* Scroll-indexed device sequence. Each scene has 181 deterministic frames.
 * Original captures are drawn intact; UI is never reconstructed in canvas.
 * Canvas is decorative: the source image and all copy remain in semantic HTML.
 */
(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  let manuallyReduced = false;
  const isReduced = () => reduce.matches || manuallyReduced;
  const compact = matchMedia('(max-width: 700px)');
  const clamp = value => Math.max(0, Math.min(1, value));
  const ease = (p, a, b) => { const t = clamp((p-a)/(b-a)); return t*t*(3-2*t); };
  const mix = (a,b,t) => a+(b-a)*t;
  const entries = [...document.querySelectorAll('.scene')].map(scene => {
    const image = scene.querySelector('.hardware img');
    const canvas = document.createElement('canvas');
    canvas.setAttribute('aria-hidden','true');
    canvas.className = 'sequence';
    const ctx = canvas.getContext('2d');
    if (image && ctx) scene.querySelector('.visual').append(canvas);
    const heading = scene.querySelector('h1,h2');
    heading.innerHTML = heading.innerHTML.split(/<br\s*\/?\s*>/i).map(line=>`<span class="headline-line">${line}</span>`).join('');
    const entry = {scene,image,canvas,ctx,frame:-1,width:0,height:0};
    image?.addEventListener('load',()=>{entry.frame=-1;request();});
    return entry;
  });
  let pending = false;
  function round(ctx,x,y,w,h,r){ctx.beginPath();ctx.roundRect(x,y,w,h,r);}
  function draw(entry, p, width, height){
    const {scene,image,canvas,ctx}=entry;
    if(!image?.naturalWidth || !ctx)return;
    const mobile=compact.matches;
    const arrive=ease(p,.12,.56), depart=ease(p,.82,1);
    const portrait=scene.classList.contains('device-reader');
    const phone=scene.classList.contains('device-phone');
    const tv=scene.classList.contains('device-tv');
    const first=scene.id==='intro';
    let w=Math.min(width*(mobile?.90:.66),height*(portrait?.37:1.2));
    if(portrait)w=Math.min(width*.48,height*.30);
    if(!portrait && !first)w=Math.min(w,height*.48*image.naturalWidth/image.naturalHeight);
    let h=w*image.naturalHeight/image.naturalWidth;
    let x=width/2, y=height*(mobile?.65:.67), angle=0, alpha=1;
    if(first){
      const shrink=ease(p,.04,.63);
      w=mix(width*1.12,Math.min(width*(mobile?.9:.52),height*1.05),shrink);
      h=w*image.naturalHeight/image.naturalWidth;
      x=mix(width/2,width*(mobile?.5:.30),shrink);
      y=mix(height*.5,height*(mobile?.67:.57),shrink);
      angle=mix(-.025,0,shrink);
    }else if(scene.id==='mac'){
      y+=height*.55*(1-arrive);angle=-.07*(1-arrive);alpha=arrive;
    }else if(scene.id==='language'){
      x+=width*.32*(1-arrive);angle=.04*(1-arrive);
    }else if(scene.id==='connections'){
      w*=.83;h*=.83;y+=height*.4*(1-arrive);alpha=arrive;
    }else if(phone){
      x-=width*.6*(1-arrive);angle=-.13*(1-arrive);
    }else if(portrait){
      y+=height*.65*(1-arrive);angle=.10*(1-arrive);alpha=arrive;
    }else if(tv){
      const expand=ease(p,.1,.65);w*=mix(.62,mobile?1:1.15,expand);h=w*image.naturalHeight/image.naturalWidth;
      alpha=ease(p,0,.15);
    }
    if(height<500 && width>height){
      w=Math.min(width*.43,height*.60*image.naturalWidth/image.naturalHeight);
      h=w*image.naturalHeight/image.naturalWidth;x=width*.74;y=height*.56;
    }
    if(mobile && height<650){
      w=Math.min(w,height*.29*image.naturalWidth/image.naturalHeight);
      h=w*image.naturalHeight/image.naturalWidth;y=height*.72;
    }
    y-=depart*height*.06;
    ctx.clearRect(0,0,width,height);
    ctx.save();ctx.globalAlpha=alpha;ctx.translate(x,y);ctx.rotate(angle);
    const border=portrait||phone?8:6;
    const radius=portrait?28:phone?24:tv?3:14;
    const gradient=ctx.createLinearGradient(-w/2,-h/2,w/2,h/2);
    gradient.addColorStop(0,'#8a8a8e');gradient.addColorStop(.3,'#18191c');gradient.addColorStop(1,'#55565c');
    ctx.shadowColor='#0006';ctx.shadowBlur=mobile?22:45;ctx.shadowOffsetY=22;
    round(ctx,-w/2-border,-h/2-border,w+border*2,h+border*2,radius);ctx.fillStyle=gradient;ctx.fill();
    ctx.shadowColor='transparent';
    ctx.save();round(ctx,-w/2,-h/2,w,h,Math.max(1,radius-border));ctx.clip();
    ctx.drawImage(image,-w/2,-h/2,w,h);ctx.restore();
    if(portrait){ctx.fillStyle='#050505';round(ctx,-w*.13,-h/2+6,w*.26,10,5);ctx.fill();ctx.fillStyle='#aaaab0';round(ctx,w/2+border,-h*.2,3,h*.12,1);ctx.fill();}
    if(!portrait&&!phone&&!tv){
      const base=ctx.createLinearGradient(0,h/2+8,0,h/2+18);base.addColorStop(0,'#b0b1b5');base.addColorStop(1,'#48494d');
      ctx.fillStyle=base;round(ctx,-w*.55,h/2+border,w*1.1,10,5);ctx.fill();
    }
    if(tv){ctx.fillStyle='#5b5c62';round(ctx,-w*.14,h/2+8,w*.28,5,2);ctx.fill();}
    ctx.restore();
    // An external visual explanation of local processing, never a fake app overlay.
    if(scene.id==='mac' && arrive>.1 && !(height<500 && width>height)){
      ctx.save();ctx.globalAlpha=arrive;
      const cy=height*(mobile?(height<650?.50:.43):.62);ctx.fillStyle=mobile?'#8f632d':'#a27138';
      for(let i=0;i<42;i++){
        const bar=6+Math.abs(Math.sin(i*.7+p*16))*22;
        round(ctx,width*(mobile?.5:.13)+(i-21)*5,cy-bar/2,2,bar,1);ctx.fill();
      }
      ctx.restore();
    }
    if(scene.id==='connections'){
      ctx.save();ctx.globalAlpha=arrive;ctx.textAlign='center';ctx.font=`500 ${mobile?12:15}px -apple-system,sans-serif`;
      ['Synology DSM','WebDAV','DLNA / UPnP'].forEach((label,i)=>{
        const bx=width/2+(i-1)*Math.min(width*.29,210), by=height*(mobile?.91:.89);
        ctx.fillStyle='#e3d4bf';round(ctx,bx-65,by-17,130,34,17);ctx.fill();ctx.fillStyle='#4d3823';ctx.fillText(label,bx,by+5);
      });ctx.restore();
    }
  }
  function render(){
    pending=false;if(isReduced())return;
    entries.forEach(entry=>{
      const {scene}=entry, rect=scene.getBoundingClientRect();
      if(rect.bottom<0||rect.top>innerHeight)return;
      const p=clamp(-rect.top/Math.max(1,rect.height-innerHeight));
      const frame=Math.round(p*180), stage=scene.querySelector('.stage');
      const width=stage.clientWidth,height=stage.clientHeight;
      if(frame===entry.frame&&width===entry.width&&height===entry.height)return;
      entry.frame=frame;entry.width=width;entry.height=height;
      scene.dataset.frame=String(frame);
      const t=frame/180, first=scene.id==='intro', visualFirst=scene.classList.contains('visual-first');
      const reveal=first?ease(t,.19,.50):visualFirst?ease(t,.04,.26):1;
      const settle=ease(t,.12,.56);
      scene.style.setProperty('--copy-opacity',reveal);
      scene.style.setProperty('--copy-y',`${(1-reveal)*36}px`);
      const copyHeight=scene.querySelector('.copy').offsetHeight;
      const destination=Math.max(height*.26,82+copyHeight/2);
      scene.style.setProperty('--copy-top',first&&!compact.matches?'48%':`${mix(height*.43,destination,first?ease(t,0,.5):settle)}px`);
      scene.style.setProperty('--line-two',first?ease(t,.30,.58):ease(t,.03,.25));
      scene.style.setProperty('--detail',first?ease(t,.42,.67):ease(t,.10,.33));
      scene.style.setProperty('--progress',t);
      if(entry.image){
        const dpr=Math.min(devicePixelRatio||1,1.5);
        const cw=Math.round(width*dpr),ch=Math.round(height*dpr);
        if(entry.canvas.width!==cw||entry.canvas.height!==ch){entry.canvas.width=cw;entry.canvas.height=ch;}
        entry.ctx.setTransform(dpr,0,0,dpr,0,0);draw(entry,t,width,height);
        scene.classList.toggle('sequence-ready',!!entry.image.naturalWidth);
      }
    });
  }
  function request(){if(!pending){pending=true;requestAnimationFrame(render);}}
  function configure(){document.documentElement.classList.toggle('cinema',!isReduced());entries.forEach(e=>e.frame=-1);request();}
  addEventListener('scroll',request,{passive:true});addEventListener('resize',request,{passive:true});
  document.querySelector('.motion-toggle')?.addEventListener('click', event => { manuallyReduced = !manuallyReduced; event.currentTarget.setAttribute('aria-pressed',String(manuallyReduced)); configure(); });
  reduce.addEventListener('change',configure);compact.addEventListener('change',configure);
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)request();});configure();
})();
