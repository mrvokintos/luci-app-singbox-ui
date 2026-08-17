'use strict';
'require view';
'require ui';
'require fs';
'require singbox-ui.share-link as shareLink';

const DIR='/etc/sing-box';
const ACTIVE=DIR+'/config.json';
const UI_DIR='/etc/singbox-ui';
const TEMPLATE=UI_DIR+'/template.json';
const TEMPLATE_DIR=UI_DIR+'/templates';
const DEFAULT_TEMPLATE='default.json';
const ACTIVE_TEMPLATE=UI_DIR+'/active-template';
const ACTIVE_META=UI_DIR+'/active-config';
const LOG_MARKER=UI_DIR+'/log-clear-marker';
const BIN='/usr/bin/sing-box';
const SERVICE='/etc/init.d/sing-box';
const HELPER='/usr/libexec/singbox-ui-helper';
const UI_VERSION='3.1.0-rc4';

const RU={
	'Configuration manager':'Менеджер конфигураций','Configs':'Конфиги','Generator':'Генератор','Template':'Шаблон','Templates':'Шаблоны','Logs':'Журнал',
	'Running':'Работает','Stopped':'Остановлен','Unavailable':'Недоступен','Start':'Запустить','Restart':'Перезапустить','Stop':'Остановить',
	'Refresh':'Обновить','New config':'Новый конфиг','Import config':'Загрузить конфиг','No JSON configs found':'JSON-конфиги не найдены',
	'Apply':'Применить','Edit':'Редактировать','Download':'Скачать','Delete':'Удалить','Active':'Применён','Back to list':'К списку',
	'Format JSON':'Форматировать JSON','Save':'Сохранить','Share link':'Ссылка подключения','Config file name':'Имя файла конфига',
	'Create config':'Создать конфиг','Supported':'Поддерживаются','Selected template':'Выбранный шаблон','New template':'Новый шаблон',
	'Delete template':'Удалить шаблон','Default template':'Стандартный','Template hint':'Шаблон содержит DNS, маршруты, входящие подключения и дополнительные outbounds. Генератор заменяет только outbound с тегом proxy.',
	'Save template':'Сохранить шаблон','Reset template':'Вернуть стандартный','Config saved':'Конфиг сохранён','Config applied':'Конфиг применён',
	'Config created':'Конфиг создан','Config imported':'Конфиг загружен','Config deleted':'Конфиг удалён','Template saved':'Шаблон сохранён',
	'Template created':'Шаблон создан','Template deleted':'Шаблон удалён','Template restored':'Шаблон восстановлен','Operation failed':'Ошибка операции',
	'Clear logs':'Очистить','Disable logs':'Отключить логи','Enable logs':'Включить логи','Logs disabled':'Логи отключены','Logs enabled':'Логи включены',
	'Invalid file name':'Недопустимое имя файла','Config is empty':'Конфиг пуст','Template must be valid JSON':'Шаблон должен быть корректным JSON',
	'Template must contain an outbounds array':'В шаблоне должен быть массив outbounds','Unsaved changes will be lost. Continue?':'Несохранённые изменения будут потеряны. Продолжить?',
	'Overwrite existing file?':'Перезаписать существующий файл?','Enter a file name':'Введите имя файла','Enter a template name':'Введите имя шаблона',
	'Delete config file permanently?':'Безвозвратно удалить файл конфига?','Delete template file permanently?':'Безвозвратно удалить файл шаблона?',
	'The default template cannot be deleted':'Стандартный шаблон удалить нельзя','The selected file is not JSON':'Выбранный файл не является JSON',
	'sing-box is not installed at /usr/bin/sing-box':'sing-box не установлен в /usr/bin/sing-box',
	'The UI never updates configs in the background. A file changes only after Save, Create config, Import, Delete, or Apply.':'UI никогда не обновляет конфиги в фоне. Файл изменяется только после команд Сохранить, Создать, Загрузить, Удалить или Применить.',
	'Nothing to show yet':'Пока нечего показывать','Updated':'Обновлено','Config editor':'Редактор конфига','New configuration':'Новая конфигурация'
};

const LANG=String(document.documentElement.lang||navigator.language||'').toLowerCase().startsWith('ru')?'ru':'en';
const _=s=>LANG==='ru'?(RU[s]||s):s;
const h=s=>String(s??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
const cleanError=s=>String(s??'').replace(/\x1b\[[0-9;]*m/g,'').trim();
const note=(type,msg)=>{
	const level=type==='error'?'error':'info';
	const body=E('p',{},String(msg));
	const timeout=type==='error'?10000:5000;
	if(typeof ui.addTimeLimitedNotification==='function')return ui.addTimeLimitedNotification(null,body,timeout,level);
	const el=ui.addNotification(null,body,level);
	setTimeout(()=>{if(el&&el.parentNode){el.classList.add('fade-out');setTimeout(()=>el.parentNode&&el.parentNode.removeChild(el),500)}},timeout);
	return el;
};

async function busy(button,fn){
	const old=button&&button.textContent;
	if(button){button.disabled=true;button.textContent='… '+old}
	try{return await fn()}finally{if(button&&button.isConnected){button.disabled=false;button.textContent=old}}
}

function validName(name){return !!name&&name.endsWith('.json')&&name!=='.'&&name!=='..'&&!name.startsWith('.')&&!/[\/\\\0]/.test(name)}
function normalizedName(name){let value=String(name||'').trim().replace(/[\/\\\0]/g,'-');if(!value.toLowerCase().endsWith('.json'))value+='.json';return value}
function pathFor(name){if(!validName(name))throw new Error(_('Invalid file name'));return DIR+'/'+name}
function templatePath(name){if(name===DEFAULT_TEMPLATE)return TEMPLATE;if(!validName(name))throw new Error(_('Invalid file name'));return TEMPLATE_DIR+'/'+name}
async function read(path,fallback=''){try{return await fs.read(path)}catch(_e){return fallback}}
function b64(value){return btoa(unescape(encodeURIComponent(value)))}

async function write(path,value){
	const text=String(value??'');
	if(new TextEncoder().encode(text).length<=52*1024)return fs.write(path,text);
	const data=b64(text);
	const prefix='/tmp/.sbui-'+Date.now()+'-'+Math.random().toString(36).slice(2)+'-';
	try{
		for(let i=0,p=0;i<data.length;i+=45*1024,p++)await fs.write(prefix+String(p).padStart(5,'0'),data.slice(i,i+45*1024));
		const result=await fs.exec(HELPER,['merge',prefix,path]);
		if((result.code|0)!==0)throw new Error(result.stderr||result.stdout||'write failed');
	}catch(error){
		try{await fs.exec(HELPER,['cleanup',prefix])}catch(_e){}
		throw error;
	}
}

async function listConfigs(){
	let entries=[];
	try{entries=await fs.list(DIR)}catch(_e){}
	return(entries||[])
		.filter(item=>validName(item.name)&&(!item.type||item.type==='file'||item.type==='regular'))
		.sort((a,b)=>a.name==='config.json'?-1:b.name==='config.json'?1:a.name.localeCompare(b.name));
}

async function listTemplates(){
	let entries=[];
	try{entries=await fs.list(TEMPLATE_DIR)}catch(_e){}
	const names=(entries||[])
		.filter(item=>validName(item.name)&&(!item.type||item.type==='file'||item.type==='regular'))
		.map(item=>item.name)
		.filter(name=>name!==DEFAULT_TEMPLATE)
		.sort((a,b)=>a.localeCompare(b));
	return[DEFAULT_TEMPLATE].concat(names);
}

async function ensureDirs(){
	const result=await fs.exec(HELPER,['ensure-dir']);
	if((result.code|0)!==0)throw new Error(result.stderr||result.stdout||'mkdir failed');
}

function size(value){const n=Number(value||0);return n<1024?n+' B':n<1048576?(n/1024).toFixed(1)+' KiB':(n/1048576).toFixed(1)+' MiB'}
function date(value){if(!value)return'—';const d=new Date(Number(value)*(Number(value)<1e11?1000:1));return isNaN(d.getTime())?'—':d.toLocaleString()}
async function hasBin(){try{await fs.stat(BIN);return true}catch(_e){return false}}

async function checkFile(path){
	if(!await hasBin())return false;
	const result=await fs.exec(BIN,['check','-c',path]);
	if((result.code|0)===0)return true;
	const message=cleanError(result.stderr||result.stdout||'sing-box check failed');
	if(/unsupported operation|unknown (command|operation)|not supported/i.test(message))return false;
	throw new Error('sing-box check: '+message);
}

async function checkText(text){
	const path='/tmp/sbui-check-'+Date.now()+'.json';
	try{await write(path,text);await checkFile(path)}finally{try{await fs.remove(path)}catch(_e){}}
}

async function service(action){
	const result=await fs.exec(SERVICE,[action]);
	if((result.code|0)!==0)throw new Error('sing-box service '+action+': '+cleanError(result.stderr||result.stdout||'failed'));
}

async function running(){try{const result=await fs.exec(SERVICE,['status']);return(result.code|0)===0||/running/i.test(result.stdout||'')}catch(_e){return false}}

const DEFAULT={
	log:{level:'info',timestamp:true},
	dns:{servers:[{type:'https',tag:'remote-dns',server:'1.1.1.1',detour:'proxy'},{type:'local',tag:'local-dns'}],strategy:'prefer_ipv4'},
	inbounds:[{type:'mixed',tag:'mixed-in',listen:'0.0.0.0',listen_port:2080}],
	outbounds:[{type:'direct',tag:'direct'},{type:'block',tag:'block'}],
	route:{rules:[{action:'sniff'},{protocol:'dns',action:'hijack-dns'},{ip_is_private:true,outbound:'direct'}],final:'proxy',auto_detect_interface:true,default_domain_resolver:'local-dns'}
};
const defaultText=()=>JSON.stringify(DEFAULT,null,2)+'\n';

function highlightJson(text){
	const token=/"(?:\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4})|[^"\\])*"|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|\b(?:true|false|null)\b|[{}\[\],:]/g;
	let result='',last=0,match;
	while((match=token.exec(text))){
		result+=h(text.slice(last,match.index));
		const value=match[0];
		let cls='json-punctuation';
		if(value[0]==='"')cls=/^\s*:/.test(text.slice(token.lastIndex))?'json-key':'json-string';
		else if(/^(true|false|null)$/.test(value))cls='json-literal';
		else if(/^-?\d/.test(value))cls='json-number';
		result+='<span class="'+cls+'">'+h(value)+'</span>';
		last=token.lastIndex;
	}
	return result+h(text.slice(last))+(text.endsWith('\n')?'':'\n');
}

function bindJsonEditor(textarea,highlight){
	const refresh=()=>{highlight.innerHTML=highlightJson(textarea.value);highlight.style.transform='translate('+(-textarea.scrollLeft)+'px,'+(-textarea.scrollTop)+'px)'};
	textarea.parentNode.classList.add('enhanced');
	textarea.addEventListener('input',refresh);
	textarea.addEventListener('scroll',refresh);
	textarea.addEventListener('keydown',event=>{
		if(event.key!=='Tab')return;
		event.preventDefault();
		const start=textarea.selectionStart,end=textarea.selectionEnd;
		textarea.setRangeText('  ',start,end,'end');
		refresh();
	});
	refresh();
	return refresh;
}

function readFileObject(file){
	if(typeof file.text==='function')return file.text();
	return new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(String(reader.result||''));reader.onerror=()=>reject(reader.error||new Error('read failed'));reader.readAsText(file)});
}

function downloadText(name,text){
	const url=URL.createObjectURL(new Blob([text],{type:'application/json;charset=utf-8'}));
	const link=document.createElement('a');
	link.href=url;
	link.download=name;
	document.body.appendChild(link);
	link.click();
	link.remove();
	setTimeout(()=>URL.revokeObjectURL(url),0);
}

const STYLE='<style>'+
'.sbox-app{max-width:1120px;margin:auto;color:var(--text-color-high,inherit)}.sbox-head{display:flex;align-items:center;gap:9px;flex-wrap:wrap;margin-bottom:16px}.sbox-head h2{margin:0 auto 0 0}.sbox-version,.sbox-binary-version{font-size:12px;padding:5px 9px;border-radius:99px;background:rgba(127,127,127,.12);color:var(--text-color-medium,inherit);white-space:nowrap}.sbox-status{display:flex;align-items:center;gap:7px;padding:5px 10px;border-radius:99px;background:rgba(127,127,127,.12);color:var(--text-color-high,inherit);white-space:nowrap}.sbox-dot{width:9px;height:9px;border-radius:50%;background:#9aa4b2;flex:none}.running .sbox-dot{background:#1fa971;box-shadow:0 0 0 3px #1fa97122}.sbox-head>button,.sbox-toolbar button,.sbox-row button{white-space:nowrap}'+
'.sbox-tabs{display:flex;gap:4px;border-bottom:1px solid #d7dde5;margin-bottom:16px;overflow:auto}.sbox-tab{border:0;background:transparent;padding:10px 15px;cursor:pointer;border-bottom:3px solid transparent}.sbox-tab.active{border-color:#1976d2;color:#1976d2;font-weight:600}.sbox-panel{display:none}.sbox-panel.active{display:block}'+
'.sbox-card{background:var(--background-color-high,#fff);border:1px solid var(--border-color-medium,#d9dfe7);border-radius:10px;padding:16px;margin-bottom:14px}.sbox-toolbar{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:12px}.sbox-toolbar .hint{margin-right:auto;color:var(--text-color-medium,#667085)}.sbox-list{display:flex;flex-direction:column;gap:9px}'+
'.sbox-row{display:grid;grid-template-columns:minmax(170px,1fr) 80px 145px repeat(4,auto);gap:9px;align-items:center;padding:12px;border:1px solid var(--border-color-medium,#e0e5ec);border-radius:8px;background:rgba(127,127,127,.08);color:var(--text-color-high,inherit)}.sbox-row.main{border-color:var(--primary-color-medium,#77aee8);box-shadow:inset 3px 0 var(--primary-color-high,#1976d2)}.sbox-name{font-weight:600;overflow-wrap:anywhere}.sbox-badge{font-size:11px;padding:2px 7px;border-radius:99px;background:var(--primary-color-low,#dcecff);color:var(--primary-color-high,#145da0);margin-left:7px}.muted{color:var(--text-color-medium,#667085);font-size:12px}'+
'.sbox-code-editor{position:relative;overflow:hidden;min-height:470px;border:1px solid var(--border-color-medium,#cfd6df);border-radius:7px;background:#111820}.sbox-editor,.sbox-highlight{box-sizing:border-box;width:100%;min-height:470px;margin:0;padding:13px;border:0;border-radius:7px;font:13px/1.55 ui-monospace,Consolas,monospace;tab-size:2;white-space:pre}.sbox-editor{position:relative;display:block;resize:vertical;background:#111820;color:#e8edf2;overflow:auto;outline:none}.sbox-highlight{position:absolute;top:0;left:0;min-width:100%;width:max-content;pointer-events:none;color:#d8dee9;background:transparent}.sbox-code-editor.enhanced .sbox-editor{background:transparent;color:transparent;-webkit-text-fill-color:transparent;caret-color:#fff}.json-key{color:#7dcfff}.json-string{color:#a6e3a1}.json-number{color:#fab387}.json-literal{color:#cba6f7}.json-punctuation{color:#bac2de}'+
'.sbox-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:12px;flex-wrap:wrap}.sbox-form{display:grid;grid-template-columns:minmax(240px,1fr) minmax(170px,240px) minmax(150px,220px) auto;gap:10px;align-items:end}.sbox-field label{display:block;font-weight:600;margin-bottom:5px}.sbox-input{box-sizing:border-box;width:100%;padding:9px;border:1px solid var(--border-color-medium,#cfd6df);border-radius:6px;background:rgba(127,127,127,.08);color:var(--text-color-high,inherit)}.sbox-select{box-sizing:border-box;min-width:180px;max-width:100%;padding:8px;border:1px solid var(--border-color-medium,#cfd6df);border-radius:6px;background:var(--background-color-high,#fff);color:var(--text-color-high,inherit)}.sbox-note{padding:10px 12px;border-radius:7px;background:rgba(127,127,127,.08);color:var(--text-color-medium,#52606d);margin:10px 0}.sbox-log{white-space:pre-wrap;overflow:auto;max-height:580px;min-height:260px;background:#111820;color:#dce4ec;border-radius:7px;padding:13px;font:12px/1.5 ui-monospace,monospace}'+
'@media(max-width:950px){.sbox-row{grid-template-columns:minmax(130px,1fr) repeat(4,auto)}.sbox-row .meta{display:none}.sbox-form{grid-template-columns:1fr 1fr}.sbox-form>button{width:100%}}@media(max-width:650px){.sbox-app{width:100%}.sbox-head h2{flex:1 0 100%;font-size:24px}.sbox-version,.sbox-binary-version,.sbox-status{font-size:11px;padding:5px 7px}.sbox-head>button{flex:1 1 30%;min-width:0;padding-left:5px;padding-right:5px;font-size:12px}.sbox-card{padding:10px}.sbox-tabs{gap:0}.sbox-tab{padding:9px 11px;white-space:nowrap}.sbox-toolbar{align-items:stretch}.sbox-toolbar .hint{flex:1 0 100%;margin-right:0}.sbox-toolbar button,.sbox-toolbar select{flex:1 1 auto}.sbox-row{grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;padding:9px}.sbox-name{grid-column:1/-1}.sbox-row button{width:100%;min-width:0;padding-left:4px;padding-right:4px;font-size:11px}.sbox-form{grid-template-columns:1fr}.sbox-code-editor,.sbox-editor,.sbox-highlight{min-height:390px}.sbox-log{padding:9px;font-size:11px}}</style>';

function jsonEditorHtml(id){return '<div class="sbox-code-editor"><pre id="'+id+'Highlight" class="sbox-highlight" aria-hidden="true"></pre><textarea id="'+id+'" class="sbox-editor" wrap="off" spellcheck="false"></textarea></div>'}

function html(){
	return STYLE+
	'<div class="sbox-head"><h2>'+h(_('Configuration manager'))+'</h2><span class="sbox-version">UI '+UI_VERSION+'</span><span id="singboxVersion" class="sbox-binary-version">sing-box …</span><span id="status" class="sbox-status"><span class="sbox-dot"></span><span>…</span></span>'+
	['start','restart','stop'].map(action=>'<button class="cbi-button cbi-button-'+(action==='stop'?'negative':action==='restart'?'apply':'positive')+'" data-service="'+action+'">'+h(_(action[0].toUpperCase()+action.slice(1)))+'</button>').join('')+'</div>'+
	'<div class="sbox-tabs">'+[['configs','Configs'],['generator','Generator'],['template','Templates'],['logs','Logs']].map((item,index)=>'<button class="sbox-tab '+(index?'':'active')+'" data-tab="'+item[0]+'">'+h(_(item[1]))+'</button>').join('')+'</div>'+
	'<section class="sbox-panel active" data-panel="configs"><div id="listView" class="sbox-card"><div class="sbox-toolbar"><span class="hint">'+h(_('The UI never updates configs in the background. A file changes only after Save, Create config, Import, Delete, or Apply.'))+'</span><input id="importFile" type="file" accept=".json,application/json" hidden><button id="import" class="cbi-button">'+h(_('Import config'))+'</button><button id="new" class="cbi-button cbi-button-positive">'+h(_('New config'))+'</button><button id="refresh" class="cbi-button">'+h(_('Refresh'))+'</button></div><div id="list" class="sbox-list"></div></div>'+
	'<div id="editView" class="sbox-card" style="display:none"><div class="sbox-toolbar"><button id="back" class="cbi-button">← '+h(_('Back to list'))+'</button><strong id="editTitle"></strong></div>'+jsonEditorHtml('editor')+'<div class="sbox-actions"><button id="format" class="cbi-button">'+h(_('Format JSON'))+'</button><button id="save" class="cbi-button cbi-button-positive">'+h(_('Save'))+'</button></div></div></section>'+
	'<section class="sbox-panel" data-panel="generator"><div class="sbox-card"><div class="sbox-note">'+h(_('Supported'))+': VLESS, VMess, Trojan, Shadowsocks, Hysteria, Hysteria2/Hy2, TUIC, SOCKS, HTTP(S).</div><div class="sbox-form"><div class="sbox-field"><label>'+h(_('Share link'))+'</label><input id="link" class="sbox-input" placeholder="vless://…"></div><div class="sbox-field"><label>'+h(_('Config file name'))+'</label><input id="generatedName" class="sbox-input" placeholder="my-server.json"></div><div class="sbox-field"><label>'+h(_('Selected template'))+'</label><select id="generatorTemplate" class="sbox-select"></select></div><button id="generate" class="cbi-button cbi-button-positive">'+h(_('Create config'))+'</button></div></div></section>'+
	'<section class="sbox-panel" data-panel="template"><div class="sbox-card"><div class="sbox-toolbar"><select id="templateSelect" class="sbox-select"></select><button id="newTemplate" class="cbi-button cbi-button-positive">'+h(_('New template'))+'</button><button id="deleteTemplate" class="cbi-button cbi-button-negative">'+h(_('Delete template'))+'</button></div><div class="sbox-note">'+h(_('Template hint'))+'</div>'+jsonEditorHtml('templateEditor')+'<div class="sbox-actions"><button id="formatTemplate" class="cbi-button">'+h(_('Format JSON'))+'</button><button id="resetTemplate" class="cbi-button">'+h(_('Reset template'))+'</button><button id="saveTemplate" class="cbi-button cbi-button-positive">'+h(_('Save template'))+'</button></div></div></section>'+
	'<section class="sbox-panel" data-panel="logs"><div class="sbox-card"><div class="sbox-toolbar"><span id="logTime" class="hint"></span><button id="toggleLogs" class="cbi-button">…</button><button id="clearLog" class="cbi-button">'+h(_('Clear logs'))+'</button><button id="refreshLog" class="cbi-button">'+h(_('Refresh'))+'</button></div><pre id="log" class="sbox-log">'+h(_('Nothing to show yet'))+'</pre></div></section>';
}

function init(root,initialConfigs,initialTemplates,initialTemplateName,initialTemplateText,initialActive,initialLogMarker){
	let configs=initialConfigs;
	let templates=initialTemplates;
	let templateName=initialTemplateName;
	let templateSaved=initialTemplateText;
	let activeName=initialActive;
	let edited=null;
	let saved='';
	let logMarker=initialLogMarker;
	const list=root.querySelector('#list');
	const editor=root.querySelector('#editor');
	const tpl=root.querySelector('#templateEditor');
	const templateSelect=root.querySelector('#templateSelect');
	const generatorTemplate=root.querySelector('#generatorTemplate');
	const configHighlight=bindJsonEditor(editor,root.querySelector('#editorHighlight'));
	const templateHighlight=bindJsonEditor(tpl,root.querySelector('#templateEditorHighlight'));
	tpl.value=initialTemplateText;
	templateHighlight();

	async function status(){const element=root.querySelector('#status'),on=await running();element.classList.toggle('running',on);element.lastElementChild.textContent=on?_('Running'):_('Stopped')}
	async function binaryVersion(){const element=root.querySelector('#singboxVersion');try{if(!await hasBin())throw new Error('missing');const result=await fs.exec(BIN,['version']),line=cleanError(result.stdout||result.stderr).split('\n')[0],match=line.match(/(?:sing-box\s+version\s+)?v?([0-9][\w.+-]*)/i);element.textContent=match?'sing-box '+match[1]:'sing-box —'}catch(_e){element.textContent='sing-box —'}}

	function renderConfigs(){
		if(!configs.length){list.innerHTML='<div class="sbox-note">'+h(_('No JSON configs found'))+'</div>';return}
		const visible=activeName&&activeName!=='config.json'?configs.filter(item=>item.name!=='config.json'):configs;
		list.innerHTML=visible.map(item=>'<div class="sbox-row '+(item.name===activeName?'main':'')+'"><div class="sbox-name">'+h(item.name)+(item.name===activeName?'<span class="sbox-badge">'+h(_('Active'))+'</span>':'')+'</div><div class="muted meta">'+h(size(item.size))+'</div><div class="muted meta">'+h(date(item.mtime))+'</div><button class="cbi-button cbi-button-apply" data-apply="'+h(item.name)+'">'+h(_('Apply'))+'</button><button class="cbi-button" data-edit="'+h(item.name)+'">'+h(_('Edit'))+'</button><button class="cbi-button" data-download="'+h(item.name)+'">'+h(_('Download'))+'</button><button class="cbi-button cbi-button-negative" data-delete="'+h(item.name)+'">'+h(_('Delete'))+'</button></div>').join('');
		list.querySelectorAll('[data-apply]').forEach(button=>button.onclick=()=>busy(button,()=>applyConfig(button.dataset.apply)));
		list.querySelectorAll('[data-edit]').forEach(button=>button.onclick=()=>openConfig(button.dataset.edit));
		list.querySelectorAll('[data-download]').forEach(button=>button.onclick=()=>busy(button,()=>downloadConfig(button.dataset.download)));
		list.querySelectorAll('[data-delete]').forEach(button=>button.onclick=()=>busy(button,()=>deleteConfig(button.dataset.delete)));
	}

	function renderTemplateOptions(){
		const options=templates.map(name=>'<option value="'+h(name)+'">'+h(name===DEFAULT_TEMPLATE?_('Default template')+' (template.json)':name)+'</option>').join('');
		templateSelect.innerHTML=options;
		generatorTemplate.innerHTML=options;
		templateSelect.value=templateName;
		generatorTemplate.value=templateName;
		root.querySelector('#deleteTemplate').disabled=templateName===DEFAULT_TEMPLATE;
	}

	async function reloadConfigs(){configs=await listConfigs();renderConfigs()}
	async function reloadTemplates(){templates=await listTemplates();if(!templates.includes(templateName))templateName=DEFAULT_TEMPLATE;renderTemplateOptions()}

	async function applyConfig(name){
		try{
			const source=pathFor(name);
			if(source!==ACTIVE){const content=await fs.read(source);await write(ACTIVE,content)}
			await service('restart');
			activeName=name;
			await write(ACTIVE_META,name+'\n');
			await reloadConfigs();await status();await logState();
			note('info',_('Config applied')+': '+name);
		}catch(error){note('error',_('Operation failed')+': '+cleanError(error.message))}
	}

	async function openConfig(name){
		if(edited&&editor.value!==saved&&!confirm(_('Unsaved changes will be lost. Continue?')))return;
		try{
			edited=name;saved=await read(pathFor(name));editor.value=saved;configHighlight();
			root.querySelector('#editTitle').textContent=_('Config editor')+': '+name;
			root.querySelector('#listView').style.display='none';root.querySelector('#editView').style.display='';editor.focus();
		}catch(error){note('error',error.message)}
	}

	function closeConfig(force){
		if(!force&&editor.value!==saved&&!confirm(_('Unsaved changes will be lost. Continue?')))return;
		edited=null;root.querySelector('#editView').style.display='none';root.querySelector('#listView').style.display='';
	}

	async function downloadConfig(name){
		try{downloadText(name,await fs.read(pathFor(name)))}catch(error){note('error',_('Operation failed')+': '+cleanError(error.message))}
	}

	async function deleteConfig(name){
		if(!confirm(_('Delete config file permanently?')+'\n\n'+name))return;
		try{
			await fs.remove(pathFor(name));
			if(edited===name){saved=editor.value;closeConfig(true)}
			if(activeName===name){
				activeName=name!=='config.json'&&configs.some(item=>item.name==='config.json')?'config.json':'';
				await write(ACTIVE_META,activeName?activeName+'\n':'');
			}
			await reloadConfigs();
			note('info',_('Config deleted')+': '+name);
		}catch(error){note('error',_('Operation failed')+': '+cleanError(error.message))}
	}

	async function importConfig(file){
		if(!file)return;
		const name=normalizedName(file.name);
		if(!validName(name))throw new Error(_('Invalid file name'));
		if(configs.some(item=>item.name===name)&&!confirm(_('Overwrite existing file?')))return;
		const text=await readFileObject(file);
		try{JSON.parse(text)}catch(_e){throw new Error(_('The selected file is not JSON'))}
		await checkText(text);await ensureDirs();await write(pathFor(name),text.endsWith('\n')?text:text+'\n');await reloadConfigs();
		note('info',_('Config imported')+': '+name);
	}

	async function switchTemplate(name,force){
		if(!templates.includes(name))return false;
		if(!force&&tpl.value!==templateSaved&&!confirm(_('Unsaved changes will be lost. Continue?'))){renderTemplateOptions();return false}
		let text=await read(templatePath(name));
		if(!text.trim())text=defaultText();
		templateName=name;templateSaved=text;tpl.value=text;templateHighlight();renderTemplateOptions();
		await ensureDirs();await write(ACTIVE_TEMPLATE,name+'\n');
		return true;
	}

	async function createTemplate(){
		const entered=prompt(_('Enter a template name'),'new-template.json');
		if(entered==null)return;
		const name=normalizedName(entered);
		if(!validName(name)||name===DEFAULT_TEMPLATE)throw new Error(_('Invalid file name'));
		if(templates.includes(name)&&!confirm(_('Overwrite existing file?')))return;
		await ensureDirs();await write(templatePath(name),defaultText());await reloadTemplates();await switchTemplate(name,true);
		note('info',_('Template created')+': '+name);
	}

	async function deleteTemplate(){
		if(templateName===DEFAULT_TEMPLATE)throw new Error(_('The default template cannot be deleted'));
		const name=templateName;
		if(!confirm(_('Delete template file permanently?')+'\n\n'+name))return;
		await fs.remove(templatePath(name));await reloadTemplates();await switchTemplate(DEFAULT_TEMPLATE,true);
		note('info',_('Template deleted')+': '+name);
	}

	async function selectTemplate(event){
		try{await switchTemplate(event.currentTarget.value,false)}catch(error){renderTemplateOptions();note('error',_('Operation failed')+': '+cleanError(error.message))}
	}

	root.querySelectorAll('[data-tab]').forEach(button=>button.onclick=()=>{
		root.querySelectorAll('[data-tab]').forEach(item=>item.classList.toggle('active',item===button));
		root.querySelectorAll('[data-panel]').forEach(item=>item.classList.toggle('active',item.dataset.panel===button.dataset.tab));
		if(button.dataset.tab==='logs')logs();
	});
	root.querySelectorAll('[data-service]').forEach(button=>button.onclick=()=>busy(button,async()=>{try{await service(button.dataset.service);await status()}catch(error){note('error',_('Operation failed')+': '+error.message)}}));
	root.querySelector('#refresh').onclick=event=>busy(event.currentTarget,reloadConfigs);
	root.querySelector('#back').onclick=()=>closeConfig(false);
	root.querySelector('#new').onclick=async()=>{
		const entered=prompt(_('Enter a file name'),'new-config.json');if(entered==null)return;
		const name=normalizedName(entered);if(!validName(name))return note('error',_('Invalid file name'));
		if(configs.some(item=>item.name===name)&&!confirm(_('Overwrite existing file?')))return;
		try{await ensureDirs();await write(pathFor(name),'{}\n');await reloadConfigs();await openConfig(name)}catch(error){note('error',_('Operation failed')+': '+error.message)}
	};
	root.querySelector('#import').onclick=()=>root.querySelector('#importFile').click();
	root.querySelector('#importFile').onchange=event=>{const input=event.currentTarget,file=input.files&&input.files[0];busy(root.querySelector('#import'),async()=>{try{await importConfig(file)}catch(error){note('error',_('Operation failed')+': '+cleanError(error.message))}finally{input.value=''}})};
	root.querySelector('#format').onclick=()=>{try{editor.value=JSON.stringify(JSON.parse(editor.value),null,2)+'\n';configHighlight()}catch(error){note('error',error.message)}};
	root.querySelector('#save').onclick=event=>busy(event.currentTarget,async()=>{
		if(!edited)return;if(!editor.value.trim())return note('error',_('Config is empty'));
		try{JSON.parse(editor.value);await checkText(editor.value);await write(pathFor(edited),editor.value);saved=editor.value;await reloadConfigs();note('info',_('Config saved')+': '+edited)}catch(error){note('error',_('Operation failed')+': '+error.message)}
	});
	root.querySelector('#generate').onclick=event=>busy(event.currentTarget,async()=>{
		try{
			const parsed=shareLink.parseShareLink(root.querySelector('#link').value);
			const name=normalizedName(root.querySelector('#generatedName').value||parsed.name||_('New configuration'));
			if(!validName(name))throw new Error(_('Invalid file name'));
			if(configs.some(item=>item.name===name)&&!confirm(_('Overwrite existing file?')))return;
			const base=JSON.parse(tpl.value);
			if(!Array.isArray(base.outbounds))throw new Error(_('Template must contain an outbounds array'));
			const output=JSON.parse(JSON.stringify(base));
			output.outbounds=output.outbounds.filter(item=>!item||item.tag!=='proxy');
			parsed.outbound.tag='proxy';output.outbounds.unshift(parsed.outbound);
			output.route=output.route&&typeof output.route==='object'?output.route:{};
			if(!output.route.default_domain_resolver){const servers=output.dns&&Array.isArray(output.dns.servers)?output.dns.servers:[],resolver=servers.find(item=>item&&item.tag==='local-dns')||servers.find(item=>item&&item.tag);if(resolver)output.route.default_domain_resolver=resolver.tag}
			const text=JSON.stringify(output,null,2)+'\n';await checkText(text);await ensureDirs();await write(pathFor(name),text);await reloadConfigs();root.querySelector('#generatedName').value=name;note('info',_('Config created')+': '+name);
		}catch(error){note('error',_('Operation failed')+': '+cleanError(error.message))}
	});
	templateSelect.onchange=selectTemplate;
	generatorTemplate.onchange=selectTemplate;
	root.querySelector('#newTemplate').onclick=event=>busy(event.currentTarget,async()=>{try{await createTemplate()}catch(error){note('error',_('Operation failed')+': '+cleanError(error.message))}});
	root.querySelector('#deleteTemplate').onclick=async event=>{await busy(event.currentTarget,async()=>{try{await deleteTemplate()}catch(error){note('error',_('Operation failed')+': '+cleanError(error.message))}});renderTemplateOptions()};
	root.querySelector('#formatTemplate').onclick=()=>{try{tpl.value=JSON.stringify(JSON.parse(tpl.value),null,2)+'\n';templateHighlight()}catch(error){note('error',_('Template must be valid JSON')+': '+error.message)}};
	root.querySelector('#saveTemplate').onclick=event=>busy(event.currentTarget,async()=>{
		try{const parsed=JSON.parse(tpl.value);if(!Array.isArray(parsed.outbounds))throw new Error(_('Template must contain an outbounds array'));tpl.value=JSON.stringify(parsed,null,2)+'\n';templateHighlight();await ensureDirs();await write(templatePath(templateName),tpl.value);templateSaved=tpl.value;note('info',_('Template saved')+': '+templateName)}catch(error){note('error',_('Template must be valid JSON')+': '+error.message)}
	});
	root.querySelector('#resetTemplate').onclick=()=>{tpl.value=defaultText();templateHighlight();note('info',_('Template restored'))};

	async function logState(){const button=root.querySelector('#toggleLogs');try{const config=JSON.parse(await read(ACTIVE));const off=config.log&&config.log.disabled===true;button.dataset.disabled=off?'1':'0';button.textContent=off?_('Enable logs'):_('Disable logs');button.classList.toggle('cbi-button-negative',!off);button.classList.toggle('cbi-button-positive',off)}catch(_e){button.disabled=true;button.textContent=_('Unavailable')}}
	async function toggleLogs(){const config=JSON.parse(await read(ACTIVE));config.log=config.log&&typeof config.log==='object'&&!Array.isArray(config.log)?config.log:{};const off=config.log.disabled===true;config.log.disabled=!off;const text=JSON.stringify(config,null,2)+'\n';await checkText(text);await write(ACTIVE,text);await service('restart');await logState();await status();note('info',off?_('Logs enabled'):_('Logs disabled'))}
	async function logText(){const result=await fs.exec('/sbin/logread',['-e','sing-box']);return String(result.stdout||'').trim()}
	async function logs(){const element=root.querySelector('#log');try{const raw=await logText(),at=logMarker?raw.lastIndexOf(logMarker):-1,shown=at>=0?raw.slice(at+logMarker.length).trim():raw;element.textContent=shown||_('Nothing to show yet');element.scrollTop=element.scrollHeight;root.querySelector('#logTime').textContent=_('Updated')+': '+new Date().toLocaleTimeString()}catch(error){element.textContent=error.message}}
	async function clearLogs(){const raw=await logText(),lines=raw.split('\n').filter(Boolean);logMarker=lines.length?lines[lines.length-1]:'';await write(LOG_MARKER,logMarker+'\n');root.querySelector('#log').textContent=_('Nothing to show yet');root.querySelector('#logTime').textContent=''}
	root.querySelector('#toggleLogs').onclick=async event=>{const button=event.currentTarget;button.disabled=true;try{await toggleLogs()}catch(error){note('error',_('Operation failed')+': '+cleanError(error.message))}finally{button.disabled=false;await logState()}};
	root.querySelector('#clearLog').onclick=event=>busy(event.currentTarget,async()=>{try{await clearLogs()}catch(error){note('error',_('Operation failed')+': '+cleanError(error.message))}});
	root.querySelector('#refreshLog').onclick=event=>busy(event.currentTarget,logs);

	renderConfigs();renderTemplateOptions();status();binaryVersion();logState();
}

return view.extend({
	handleSave:null,handleSaveApply:null,handleReset:null,
	async render(){
		const configs=await listConfigs();
		const templates=await listTemplates();
		let templateName=(await read(ACTIVE_TEMPLATE,DEFAULT_TEMPLATE)).trim();
		if(!templates.includes(templateName))templateName=DEFAULT_TEMPLATE;
		let templateText=await read(templatePath(templateName));
		if(!templateText.trim())templateText=defaultText();
		let activeName=(await read(ACTIVE_META,'config.json')).trim();
		if(!configs.some(item=>item.name===activeName))activeName=configs.some(item=>item.name==='config.json')?'config.json':'';
		const logMarker=(await read(LOG_MARKER)).trim();
		const root=E('div',{class:'sbox-app'});root.innerHTML=html();
		setTimeout(()=>init(root,configs,templates,templateName,templateText,activeName,logMarker),0);
		return root;
	}
});
