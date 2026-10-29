'use strict';
(() => {
  const q = (s) => document.querySelector(s);
  const page = document.body.dataset.page;
  document.querySelectorAll(`[data-nav="${page}"]`).forEach((a) => { a.classList.add('active'); a.setAttribute('aria-current', 'page'); });
  const menu = q('#mobile-menu');
  if (menu) menu.addEventListener('click', () => { const open = q('#nav-links').classList.toggle('open'); menu.setAttribute('aria-expanded', String(open)); menu.textContent = open ? '× CLOSE' : '☰ MENU'; });
  document.querySelectorAll('#nav-links a').forEach(a => a.addEventListener('click', () => { q('#nav-links').classList.remove('open'); if (menu) menu.setAttribute('aria-expanded','false'); }));
  const types = { netrunner: {symbol:'⌘',name:'THE NETRUNNER',description:'Reality is just another system to break.',strength:'PRIMARY ATTRIBUTE: TECH',skill:'CYBERWARFARE',number:'01'},solo:{symbol:'✛',name:'THE SOLO',description:'Contracts end. Your reputation doesn’t.',strength:'PRIMARY ATTRIBUTE: EDGE',skill:'CLOSE COMBAT',number:'02'},ghost:{symbol:'◈',name:'THE GHOST',description:'Nothing moves in the dark without you knowing.',strength:'PRIMARY ATTRIBUTE: GHOST',skill:'INFILTRATION',number:'03'},techie:{symbol:'⚙',name:'THE TECHIE',description:'If it has a circuit, you can make it sing.',strength:'PRIMARY ATTRIBUTE: TECH',skill:'ENGINEERING',number:'04'},fixer:{symbol:'◇',name:'THE FIXER',description:'Everybody has a price. You know the exchange rate.',strength:'PRIMARY ATTRIBUTE: GHOST',skill:'NEGOTIATION',number:'05'} };
  document.querySelectorAll('[data-class]').forEach(button => button.addEventListener('click', () => {
    const role=types[button.dataset.class]; if (!role) return;
    document.querySelectorAll('[data-class]').forEach(b=>{b.classList.toggle('active',b===button); b.setAttribute('aria-selected', String(b===button));});
    q('#role-number').textContent=`CLASS_${role.number}`; q('#role-symbol').textContent=role.symbol; q('#role-name').textContent=role.name;
    q('#role-tagline').textContent=role.description; q('#role-strength').textContent=role.strength; q('#role-skill').textContent=role.skill;
    q('#selected-class-link').href=`/play?mode=create&role=${encodeURIComponent(button.dataset.class)}`;
  }));
  const status=q('#gm-health-status');
  if(status){
    fetch('/health',{cache:'no-store'}).then(response => { if(!response.ok) throw new Error('offline'); return response.json(); }).then(data=>{
      status.textContent = data.gm_mode === 'demo' ? '● DEMO CORE ONLINE' : data.gm_mode === 'gemini' ? '● GEMINI KEY CONFIGURED' : '● GM NOT CONFIGURED';
    }).catch(()=>{status.textContent='○ DEMO PREVIEW / UPLINK OFFLINE';});
  }
  const grid=q('#hero-grid');
  if (grid) {
    const walls=new Set([3,4,5,17,19,20,31,34,36,46,47,61,69,70,75,76,88,89,103,104,115,116]);
    const covers=new Set([8,23,37,53,92,98,112]); const hazards=new Set([41,55,56,96]);
    for(let i=0;i<126;i++){
      const cell=document.createElement('div'); cell.className='cell';
      if (walls.has(i)) cell.classList.add('wall'); else if(covers.has(i)) cell.classList.add('cover'); else if(hazards.has(i)) cell.classList.add('hazard');
      if(i===83) cell.classList.add('objective');
      const token={74:'1',87:'2',101:'3'}[i]; if(token){ cell.className=`cell token ${token==='1'?'':`t${token}`}`;cell.dataset.token=token;}
      grid.append(cell);
    }
  }
  try {
    const room = localStorage.getItem('neon:lastRoom');
    if (room && /^[A-HJ-NP-Z2-9]{8}$/.test(room) && localStorage.getItem(`neon:token:${room}`)) {
      const resume=q('#resume-link'); if (resume) {resume.hidden=false; resume.href=`/play?room=${encodeURIComponent(room)}`;}
    }
  } catch (_) { /* Local storage is optional in restricted browsing modes. */ }
})();
