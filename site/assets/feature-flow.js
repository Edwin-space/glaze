/* Prepared walkthrough, with real browser playback and timed subtitle selection.
 * It does not run speech recognition or translation in the visitor's browser.
 */
(() => {
  const root=document.querySelector('.feature-flow');if(!root)return;
  const en=document.documentElement.lang==='en';
  const choose=(ko,english)=>en?english:ko;
  const video=root.querySelector('video');
  const player=root.querySelector('.functional-device');
  const cueList=root.querySelector('.cue-list');
  const caption=root.querySelector('.demo-subtitle');
  const modes=[...root.querySelectorAll('[data-subtitle]')];
  const jumps=[...root.querySelectorAll('[data-step]')];
  const titles=[choose('나의 영상에서 시작합니다.','Start with your video.'),choose('목소리를 듣고, 문장으로.','Listen to a voice. Find the words.'),choose('원어 그대로, 공부할 때도.','Keep the original. Learn every word.'),choose('내가 이해하는 언어로.','Choose the language you understand.'),choose('자막도 나의 파일로.','Keep subtitles with your video.'),choose('이제, 나의 손 안에서.','Now, take it with you.')];
  const descriptions=[choose('하나의 샘플 영상으로 모든 단계를 이어갑니다.','One sample video connects every step.'),choose('Apple Silicon Mac에서 음성을 인식하는 흐름을 보여줍니다.','Follow speech recognition on Apple Silicon Mac.'),choose('영어 음성에서 영문 자막으로. 영상과 문장을 함께 확인하세요.','English speech, English captions. Follow the video and the words.'),choose('원어·한국어 번역·원어와 번역을 직접 선택해 보세요.','Switch between English, Korean, or both below.'),choose('영상과 자막을 함께 준비한 뒤, 휴대폰에 미리 복사하세요.','Prepare your video and subtitle files, then copy them to your phone.'),choose('같은 예시를 iPhone 18 Pro 목업에서 재생합니다. 자동 파일·재생 위치 동기화 시연은 아닙니다.','Play the same example in an iPhone 18 Pro mockup. This does not demonstrate automatic file or playback syncing.')];
  const originals=['Every story begins with a voice.','Read the original words.','Choose the language you understand.','Take your stories with you.'];
  const translations=['모든 이야기는 목소리에서 시작됩니다.','원어 그대로 읽어보세요.','내가 이해하는 언어를 선택하세요.','나의 이야기를 가지고 떠나세요.'];
  const cues=[{start:0,end:3.5},{start:3.5,end:6.2},{start:6.2,end:10},{start:10,end:14.5}];
  let current=-1,mode='original',pending=false;
  function updateCaptions(){
    if(video.currentTime>14.5)video.currentTime=0;
    const i=cues.findIndex(c=>video.currentTime>=c.start&&video.currentTime<c.end);
    caption.textContent=current<2||i<0?'':mode==='both'?`${originals[i]}\n${translations[i]}`:mode==='translated'?translations[i]:originals[i];
    root.querySelector('.demo-seek').value=String(video.currentTime);
    root.querySelector('.demo-time').textContent=`0:${Math.floor(video.currentTime).toString().padStart(2,'0')}`;
    [...cueList.children].forEach((li,index)=>li.classList.toggle('speaking',index===i));
  }
  function selectMode(next){mode=next;modes.forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.subtitle===mode)));updateCaptions();}
  function play(){video.play().catch(()=>{root.querySelector('.demo-play').textContent=choose('눌러서 재생','Tap to play');});}
  function setStep(index){
    if(current===index)return;current=index;root.dataset.phase=String(index);
    player.dataset.view=index===5?'phone':'mac';
    root.querySelector('.feature-title').textContent=titles[index];
    root.querySelector('.feature-description').textContent=descriptions[index];
    root.querySelector('.hardware-label').textContent=index===5?'iPhone 18 Pro · '+choose('디자인 목업','design mockup'):'Apple Silicon Mac · macOS 26+';
    root.querySelector('.demo-device-name').textContent=index===5?'iPhone 18 Pro':'Apple Silicon Mac';
    const states=[choose('자막 없는 영상','Video without subtitles'),choose('음성 인식 과정 · 예시','Speech recognition · example'),choose('English · 원어 자막','English · original captions'),choose('번역 자막 선택','Choose translated captions'),choose('영상 곁에 보관','Keep beside your video'),choose('모바일 재생','Mobile playback')];
    root.querySelector('.demo-state').textContent=states[index];
    jumps.forEach((button,i)=>{if(i===index)button.setAttribute('aria-current','step');else button.removeAttribute('aria-current');});
    if(index===2)selectMode('original');
    if(index===3)selectMode('translated');
    if(index>0)play();else video.pause();
    updateCaptions();
  }
  function update(){
    pending=false;
    if(!document.documentElement.classList.contains('cinema'))return;
    const rect=root.getBoundingClientRect();
    if(rect.bottom<0||rect.top>innerHeight){video.pause();return;}
    const p=Math.max(0,Math.min(.9999,-rect.top/Math.max(1,root.offsetHeight-innerHeight)));
    const step=Math.floor(p*6);setStep(step);
    if(step===1){const revealed=Math.max(1,Math.ceil((p*6-step)*4));[...cueList.children].forEach((li,i)=>li.classList.toggle('recognized',i<revealed));}
  }
  function request(){if(!pending){pending=true;requestAnimationFrame(update);}}
  function goTo(index){
    if(!document.documentElement.classList.contains('cinema')){setStep(index);return;}
    scrollTo({top:root.getBoundingClientRect().top+scrollY+(root.offsetHeight-innerHeight)*(index+.15)/6,behavior:'instant'});
  }
  cueList.innerHTML=originals.map((text,i)=>`<li><time>00:${Math.floor(cues[i].start).toString().padStart(2,'0')}</time><span>${text}</span></li>`).join('');
  jumps.forEach(button=>button.addEventListener('click',()=>goTo(Number(button.dataset.step))));
  modes.forEach(button=>button.addEventListener('click',()=>selectMode(button.dataset.subtitle)));
  video.controls=false;
  root.querySelector('.demo-play').addEventListener('click',()=>{if(video.paused)play();else video.pause();});
  root.querySelector('.demo-audio').addEventListener('click',event=>{video.muted=!video.muted;event.currentTarget.setAttribute('aria-pressed',String(!video.muted));event.currentTarget.textContent=video.muted?choose('소리 켜기','Sound on'):choose('음소거','Mute');});
  root.querySelector('.demo-seek').addEventListener('input',event=>{video.currentTime=Number(event.target.value);updateCaptions();});
  video.addEventListener('timeupdate',updateCaptions);
  video.addEventListener('play',()=>root.querySelector('.demo-play').textContent=choose('일시정지','Pause'));
  video.addEventListener('pause',()=>root.querySelector('.demo-play').textContent=choose('재생','Play'));
  video.addEventListener('loadedmetadata',()=>root.querySelector('.demo-seek').max=String(video.duration));
  document.querySelectorAll('a[href="#on-the-go"],a[href="#language"]').forEach(a=>a.addEventListener('click',event=>{event.preventDefault();goTo(a.hash==='#on-the-go'?5:3);}));
  document.addEventListener('visibilitychange',()=>{if(document.hidden)video.pause();else request();});
  addEventListener('scroll',request,{passive:true});addEventListener('resize',request,{passive:true});setStep(0);request();
})();
