'use strict';
'require view';
'require ui';
'require fs';
'require singbox-ui.share-link as shareLink';

const DIR='/etc/sing-box', ACTIVE=DIR+'/config.json', TEMPLATE='/etc/singbox-ui/template.json', ACTIVE_META='/etc/singbox-ui/active-config';
const BIN='/usr/bin/sing-box', SERVICE='/etc/init.d/sing-box', HELPER='/usr/libexec/singbox-ui-helper';
const UI_VERSION='3.0.5';
const RU={
'Configuration manager':'Менеджер конфигураций','Configs':'Конфиги','Generator':'Генератор','Template':'Шаблон','Logs':'Журнал',
'Running':'Работает','Stopped':'Остановлен','Unavailable':'Недоступен','Start':'Запустить','Restart':'Перезапустить','Stop':'Остановить',
'Refresh':'Обновить','New config':'Новый конфиг','No JSON configs found':'JSON-конфиги не найдены','Apply':'Применить','Edit':'Редактировать',
'Active':'Применён','Back to list':'К списку','Format JSON':'Форматировать JSON','Save':'Сохранить','Share link':'Ссылка подключения',
'Config file name':'Имя файла конфига','Create config':'Создать конфиг','Supported':'Поддерживаются',
'Template hint':'Шаблон содержит DNS, маршруты, входящие подключения и дополнительные outbounds. Генератор заменяет только outbound с тегом proxy.',
'Save template':'Сохранить шаблон','Reset template':'Вернуть стандартный','Config saved':'Конфиг сохранён','Config applied':'Конфиг применён',
'Config created':'Конфиг создан','Template saved':'Шаблон сохранён','Template restored':'Шаблон восстановлен','Operation failed':'Ошибка операции',
'Invalid file name':'Недопустимое имя файла','Config is empty':'Конфиг пуст','Template must be valid JSON':'Шаблон должен быть корректным JSON',
'Template must contain an outbounds array':'В шаблоне должен быть массив outbounds','Unsaved changes will be lost. Continue?':'Несохранённые изменения будут потеряны. Продолжить?',
'Overwrite existing file?':'Перезаписать существующий файл?','Enter a file name':'Введите имя файла',
'sing-box is not installed at /usr/bin/sing-box':'sing-box не установлен в /usr/bin/sing-box',
'The UI never updates configs in the background. A file changes only after Save, Create config, or Apply.':'UI никогда не обновляет конфиги в фоне. Файл изменяется только после команд Сохранить, Создать конфиг или Применить.',
'Nothing to show yet':'Пока нечего показывать','Updated':'Обновлено','Config editor':'Редактор конфига','New configuration':'Новая конфигурация'};
const LANG=String(document.documentElement.lang||navigator.language||'').toLowerCase().startsWith('ru')?'ru':'en';
const _=s=>LANG==='ru'?(RU[s]||s):s;
const h=s=>String(s??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
const cleanError=s=>String(s??'').replace(/\x1b\[[0-9;]*m/g,'').trim();
const note=(type,msg)=>ui.addNotification(null,E('p',{},String(msg)),type==='error'?'error':'info');
async function busy(b,fn){const old=b&&b.textContent;if(b){b.disabled=true;b.textContent='… '+old}try{return await fn()}finally{if(b&&b.isConnected){b.disabled=false;b.textContent=old}}}
function validName(n){return !!n&&n.endsWith('.json')&&n!=='.'&&n!=='..'&&!n.startsWith('.')&&!/[\/\\\0]/.test(n)}
function normalizedName(n){let v=String(n||'').trim().replace(/[\/\\\0]/g,'-');if(!v.toLowerCase().endsWith('.json'))v+='.json';return v}
function pathFor(n){if(!validName(n))throw new Error(_('Invalid file name'));return DIR+'/'+n}
async function read(path,fallback=''){try{return await fs.read(path)}catch(_e){return fallback}}
function b64(s){return btoa(unescape(encodeURIComponent(s)))}
async function write(path,value){
	const s=String(value??'');
	if(new TextEncoder().encode(s).length<=52*1024)return fs.write(path,s);
	const data=b64(s),prefix='/tmp/.sbui-'+Date.now()+'-'+Math.random().toString(36).slice(2)+'-';
	try{
		for(let i=0,p=0;i<data.length;i+=45*1024,p++)await fs.write(prefix+String(p).padStart(5,'0'),data.slice(i,i+45*1024));
		const r=await fs.exec(HELPER,['merge',prefix,path]);if((r.code|0)!==0)throw new Error(r.stderr||r.stdout||'write failed');
	}catch(e){try{await fs.exec(HELPER,['cleanup',prefix])}catch(_e){}throw e}
}
async function listConfigs(){
	let a=[];try{a=await fs.list(DIR)}catch(_e){}
	return(a||[]).filter(x=>validName(x.name)&&(!x.type||x.type==='file'||x.type==='regular')).sort((a,b)=>a.name==='config.json'?-1:b.name==='config.json'?1:a.name.localeCompare(b.name));
}
async function ensureConfigDir(){const r=await fs.exec(HELPER,['ensure-dir']);if((r.code|0)!==0)throw new Error(r.stderr||r.stdout||'mkdir failed')}
function size(n){n=Number(n||0);return n<1024?n+' B':n<1048576?(n/1024).toFixed(1)+' KiB':(n/1048576).toFixed(1)+' MiB'}
function date(n){if(!n)return'—';const d=new Date(Number(n)*(Number(n)<1e11?1000:1));return isNaN(d.getTime())?'—':d.toLocaleString()}
async function hasBin(){try{await fs.stat(BIN);return true}catch(_e){return false}}
async function checkFile(path){
	if(!await hasBin())return false;
	const r=await fs.exec(BIN,['check','-c',path]);
	if((r.code|0)===0)return true;
	const message=cleanError(r.stderr||r.stdout||'sing-box check failed');
	if(/unsupported operation|unknown (command|operation)|not supported/i.test(message))return false;
	throw new Error('sing-box check: '+message);
}
async function checkText(text){const p='/tmp/sbui-check-'+Date.now()+'.json';try{await write(p,text);await checkFile(p)}finally{try{await fs.remove(p)}catch(_e){}}}
async function service(action){const r=await fs.exec(SERVICE,[action]);if((r.code|0)!==0)throw new Error('sing-box service '+action+': '+cleanError(r.stderr||r.stdout||'failed'))}
async function running(){try{const r=await fs.exec(SERVICE,['status']);return(r.code|0)===0||/running/i.test(r.stdout||'')}catch(_e){return false}}

const DEFAULT={
 log:{level:'info',timestamp:true},
 dns:{servers:[{type:'https',tag:'remote-dns',server:'1.1.1.1',detour:'proxy'},{type:'local',tag:'local-dns'}],strategy:'prefer_ipv4'},
 inbounds:[{type:'mixed',tag:'mixed-in',listen:'0.0.0.0',listen_port:2080}],
 outbounds:[{type:'direct',tag:'direct'},{type:'block',tag:'block'}],
 route:{rules:[{action:'sniff'},{protocol:'dns',action:'hijack-dns'},{ip_is_private:true,outbound:'direct'}],final:'proxy',auto_detect_interface:true,default_domain_resolver:'local-dns'}
};
const STYLE='<style>'+
'.sbox-app{max-width:1040px;margin:auto;color:var(--text-color-high,inherit)}.sbox-head{display:flex;align-items:center;gap:9px;flex-wrap:wrap;margin-bottom:16px}.sbox-head h2{margin:0 auto 0 0}.sbox-version{font-size:12px;font-weight:400;opacity:.55;margin-left:8px}.sbox-status{display:flex;align-items:center;gap:7px;padding:5px 10px;border-radius:99px;background:rgba(127,127,127,.12);color:var(--text-color-high,inherit)}.sbox-dot{width:9px;height:9px;border-radius:50%;background:#9aa4b2}.running .sbox-dot{background:#1fa971;box-shadow:0 0 0 3px #1fa97122}'+
'.sbox-tabs{display:flex;gap:4px;border-bottom:1px solid #d7dde5;margin-bottom:16px;overflow:auto}.sbox-tab{border:0;background:transparent;padding:10px 15px;cursor:pointer;border-bottom:3px solid transparent}.sbox-tab.active{border-color:#1976d2;color:#1976d2;font-weight:600}.sbox-panel{display:none}.sbox-panel.active{display:block}'+
'.sbox-card{background:var(--background-color-high,#fff);border:1px solid var(--border-color-medium,#d9dfe7);border-radius:10px;padding:16px;margin-bottom:14px}.sbox-toolbar{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:12px}.sbox-toolbar .hint{margin-right:auto;color:var(--text-color-medium,#667085)}.sbox-list{display:flex;flex-direction:column;gap:9px}'+
'.sbox-row{display:grid;grid-template-columns:minmax(180px,1fr) 110px 170px auto auto;gap:12px;align-items:center;padding:12px;border:1px solid var(--border-color-medium,#e0e5ec);border-radius:8px;background:rgba(127,127,127,.08);color:var(--text-color-high,inherit)}.sbox-row.main{border-color:var(--primary-color-medium,#77aee8);box-shadow:inset 3px 0 var(--primary-color-high,#1976d2)}.sbox-name{font-weight:600;overflow-wrap:anywhere}.sbox-badge{font-size:11px;padding:2px 7px;border-radius:99px;background:var(--primary-color-low,#dcecff);color:var(--primary-color-high,#145da0);margin-left:7px}.muted{color:var(--text-color-medium,#667085);font-size:12px}'+
'.sbox-editor{width:100%;min-height:470px;box-sizing:border-box;padding:13px;border:1px solid var(--border-color-medium,#cfd6df);border-radius:7px;background:#111820;color:#e8edf2;font:13px/1.55 ui-monospace,Consolas,monospace;tab-size:2;resize:vertical}.sbox-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:12px;flex-wrap:wrap}.sbox-form{display:grid;grid-template-columns:1fr 240px auto;gap:10px;align-items:end}.sbox-field label{display:block;font-weight:600;margin-bottom:5px}.sbox-input{box-sizing:border-box;width:100%;padding:9px;border:1px solid var(--border-color-medium,#cfd6df);border-radius:6px;background:rgba(127,127,127,.08);color:var(--text-color-high,inherit)}.sbox-note{padding:10px 12px;border-radius:7px;background:rgba(127,127,127,.08);color:var(--text-color-medium,#52606d);margin:10px 0}.sbox-log{white-space:pre-wrap;overflow:auto;max-height:580px;min-height:260px;background:#111820;color:#dce4ec;border-radius:7px;padding:13px;font:12px/1.5 ui-monospace,monospace}'+
'@media(max-width:800px){.sbox-row{grid-template-columns:1fr auto auto}.sbox-row .meta{display:none}.sbox-form{grid-template-columns:1fr}}@media(max-width:520px){.sbox-row{grid-template-columns:1fr 1fr}.sbox-name{grid-column:1/-1}.sbox-row button{width:100%}}</style>';
function html(){
 return STYLE+'<div class="sbox-head"><h2>'+h(_('Configuration manager'))+'<small class="sbox-version">v'+UI_VERSION+'</small></h2><span id="status" class="sbox-status"><span class="sbox-dot"></span><span>…</span></span>'+
 ['start','restart','stop'].map(a=>'<button class="cbi-button cbi-button-'+(a==='stop'?'negative':a==='restart'?'apply':'positive')+'" data-service="'+a+'">'+h(_(a[0].toUpperCase()+a.slice(1)))+'</button>').join('')+'</div>'+
 '<div class="sbox-tabs">'+[['configs','Configs'],['generator','Generator'],['template','Template'],['logs','Logs']].map((x,i)=>'<button class="sbox-tab '+(i?'':'active')+'" data-tab="'+x[0]+'">'+h(_(x[1]))+'</button>').join('')+'</div>'+
 '<section class="sbox-panel active" data-panel="configs"><div id="listView" class="sbox-card"><div class="sbox-toolbar"><span class="hint">'+h(_('The UI never updates configs in the background. A file changes only after Save, Create config, or Apply.'))+'</span><button id="new" class="cbi-button cbi-button-positive">'+h(_('New config'))+'</button><button id="refresh" class="cbi-button">'+h(_('Refresh'))+'</button></div><div id="list" class="sbox-list"></div></div>'+
 '<div id="editView" class="sbox-card" style="display:none"><div class="sbox-toolbar"><button id="back" class="cbi-button">← '+h(_('Back to list'))+'</button><strong id="editTitle"></strong></div><textarea id="editor" class="sbox-editor" spellcheck="false"></textarea><div class="sbox-actions"><button id="format" class="cbi-button">'+h(_('Format JSON'))+'</button><button id="save" class="cbi-button cbi-button-positive">'+h(_('Save'))+'</button></div></div></section>'+
 '<section class="sbox-panel" data-panel="generator"><div class="sbox-card"><div class="sbox-note">'+h(_('Supported'))+': VLESS, VMess, Trojan, Shadowsocks, Hysteria, Hysteria2/Hy2, TUIC, SOCKS, HTTP(S).</div><div class="sbox-form"><div class="sbox-field"><label>'+h(_('Share link'))+'</label><input id="link" class="sbox-input" placeholder="vless://…"></div><div class="sbox-field"><label>'+h(_('Config file name'))+'</label><input id="generatedName" class="sbox-input" placeholder="my-server.json"></div><button id="generate" class="cbi-button cbi-button-positive">'+h(_('Create config'))+'</button></div></div></section>'+
 '<section class="sbox-panel" data-panel="template"><div class="sbox-card"><div class="sbox-note">'+h(_('Template hint'))+'</div><textarea id="templateEditor" class="sbox-editor" spellcheck="false"></textarea><div class="sbox-actions"><button id="resetTemplate" class="cbi-button">'+h(_('Reset template'))+'</button><button id="saveTemplate" class="cbi-button cbi-button-positive">'+h(_('Save template'))+'</button></div></div></section>'+
 '<section class="sbox-panel" data-panel="logs"><div class="sbox-card"><div class="sbox-toolbar"><span id="logTime" class="hint"></span><button id="refreshLog" class="cbi-button">'+h(_('Refresh'))+'</button></div><pre id="log" class="sbox-log">'+h(_('Nothing to show yet'))+'</pre></div></section>';
}
function init(root,initial,template,initialActive){
 let configs=initial,activeName=initialActive,edited=null,saved='',list=root.querySelector('#list'),editor=root.querySelector('#editor'),tpl=root.querySelector('#templateEditor');
 tpl.value=template;
 async function status(){const e=root.querySelector('#status'),on=await running();e.classList.toggle('running',on);e.lastElementChild.textContent=on?_('Running'):_('Stopped')}
 function render(){
  if(!configs.length){list.innerHTML='<div class="sbox-note">'+h(_('No JSON configs found'))+'</div>';return}
  list.innerHTML=configs.map(x=>'<div class="sbox-row '+(x.name===activeName?'main':'')+'"><div class="sbox-name">'+h(x.name)+(x.name===activeName?'<span class="sbox-badge">'+h(_('Active'))+'</span>':'')+'</div><div class="muted meta">'+h(size(x.size))+'</div><div class="muted meta">'+h(date(x.mtime))+'</div><button class="cbi-button cbi-button-apply" data-apply="'+h(x.name)+'">'+h(_('Apply'))+'</button><button class="cbi-button" data-edit="'+h(x.name)+'">'+h(_('Edit'))+'</button></div>').join('');
  list.querySelectorAll('[data-apply]').forEach(b=>b.onclick=()=>busy(b,()=>apply(b.dataset.apply)));
  list.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>open(b.dataset.edit));
 }
 async function reload(){configs=await listConfigs();render()}
 async function apply(name){try{const src=pathFor(name);if(src!==ACTIVE){const content=await fs.read(src);await write(ACTIVE,content)}await service('restart');activeName=name;await write(ACTIVE_META,name+'\n');await reload();await status();note('info',_('Config applied')+': '+name)}catch(e){note('error',_('Operation failed')+': '+cleanError(e.message))}}
 async function open(name){if(edited&&editor.value!==saved&&!confirm(_('Unsaved changes will be lost. Continue?')))return;try{edited=name;saved=await read(pathFor(name));editor.value=saved;root.querySelector('#editTitle').textContent=_('Config editor')+': '+name;root.querySelector('#listView').style.display='none';root.querySelector('#editView').style.display='';editor.focus()}catch(e){note('error',e.message)}}
 function close(){if(editor.value!==saved&&!confirm(_('Unsaved changes will be lost. Continue?')))return;edited=null;root.querySelector('#editView').style.display='none';root.querySelector('#listView').style.display=''}
 root.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>{root.querySelectorAll('[data-tab]').forEach(x=>x.classList.toggle('active',x===b));root.querySelectorAll('[data-panel]').forEach(x=>x.classList.toggle('active',x.dataset.panel===b.dataset.tab));if(b.dataset.tab==='logs')logs()});
 root.querySelectorAll('[data-service]').forEach(b=>b.onclick=()=>busy(b,async()=>{try{await service(b.dataset.service);await status()}catch(e){note('error',_('Operation failed')+': '+e.message)}}));
 root.querySelector('#refresh').onclick=e=>busy(e.currentTarget,reload);root.querySelector('#back').onclick=close;
 root.querySelector('#new').onclick=async()=>{const entered=prompt(_('Enter a file name'),'new-config.json');if(entered==null)return;const name=normalizedName(entered);if(!validName(name))return note('error',_('Invalid file name'));if(configs.some(x=>x.name===name)&&!confirm(_('Overwrite existing file?')))return;try{await ensureConfigDir();await write(pathFor(name),'{}\n');await reload();await open(name)}catch(e){note('error',_('Operation failed')+': '+e.message)}};
 root.querySelector('#format').onclick=()=>{try{editor.value=JSON.stringify(JSON.parse(editor.value),null,2)+'\n'}catch(e){note('error',e.message)}};
 root.querySelector('#save').onclick=e=>busy(e.currentTarget,async()=>{if(!edited)return;if(!editor.value.trim())return note('error',_('Config is empty'));try{await checkText(editor.value);await write(pathFor(edited),editor.value);saved=editor.value;await reload();note('info',_('Config saved')+': '+edited)}catch(err){note('error',_('Operation failed')+': '+err.message)}});
 root.querySelector('#generate').onclick=e=>busy(e.currentTarget,async()=>{try{const p=shareLink.parseShareLink(root.querySelector('#link').value),name=normalizedName(root.querySelector('#generatedName').value||p.name||_('New configuration'));if(!validName(name))throw new Error(_('Invalid file name'));if(configs.some(x=>x.name===name)&&!confirm(_('Overwrite existing file?')))return;const t=JSON.parse(tpl.value);if(!Array.isArray(t.outbounds))throw new Error(_('Template must contain an outbounds array'));const out=JSON.parse(JSON.stringify(t));out.outbounds=out.outbounds.filter(x=>!x||x.tag!=='proxy');p.outbound.tag='proxy';out.outbounds.unshift(p.outbound);out.route=out.route&&typeof out.route==='object'?out.route:{};if(!out.route.default_domain_resolver){const servers=out.dns&&Array.isArray(out.dns.servers)?out.dns.servers:[],resolver=servers.find(x=>x&&x.tag==='local-dns')||servers.find(x=>x&&x.tag);if(resolver)out.route.default_domain_resolver=resolver.tag}const text=JSON.stringify(out,null,2)+'\n';await checkText(text);await ensureConfigDir();await write(pathFor(name),text);await reload();root.querySelector('#generatedName').value=name;note('info',_('Config created')+': '+name)}catch(err){note('error',_('Operation failed')+': '+cleanError(err.message))}});
 root.querySelector('#saveTemplate').onclick=e=>busy(e.currentTarget,async()=>{try{const t=JSON.parse(tpl.value);if(!Array.isArray(t.outbounds))throw new Error(_('Template must contain an outbounds array'));tpl.value=JSON.stringify(t,null,2)+'\n';await write(TEMPLATE,tpl.value);note('info',_('Template saved'))}catch(err){note('error',_('Template must be valid JSON')+': '+err.message)}});
 root.querySelector('#resetTemplate').onclick=()=>{tpl.value=JSON.stringify(DEFAULT,null,2)+'\n';note('info',_('Template restored'))};
 async function logs(){const el=root.querySelector('#log');try{const r=await fs.exec('/sbin/logread',['-e','sing-box']);el.textContent=String(r.stdout||'').trim()||_('Nothing to show yet');el.scrollTop=el.scrollHeight;root.querySelector('#logTime').textContent=_('Updated')+': '+new Date().toLocaleTimeString()}catch(e){el.textContent=e.message}}
 root.querySelector('#refreshLog').onclick=e=>busy(e.currentTarget,logs);render();status();
}
return view.extend({handleSave:null,handleSaveApply:null,handleReset:null,async render(){const configs=await listConfigs();let template=await read(TEMPLATE);if(!template.trim())template=JSON.stringify(DEFAULT,null,2)+'\n';let activeName=(await read(ACTIVE_META,'config.json')).trim();if(!configs.some(x=>x.name===activeName))activeName=configs.some(x=>x.name==='config.json')?'config.json':'';const root=E('div',{class:'sbox-app'});root.innerHTML=html();setTimeout(()=>init(root,configs,template,activeName),0);return root}});
