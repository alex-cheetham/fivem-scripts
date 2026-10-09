(() => {
    const $ = (id) => document.getElementById(id);
    const RES = window.GetParentResourceName ? window.GetParentResourceName() : 'statewide_police';
    const post = (name, data) => fetch(`https://${RES}/${name}`, { method: 'POST', body: JSON.stringify(data || {}) })
        .then((r) => r.json()).catch(() => ({}));
    const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const money = (n) => '$' + Math.round(n || 0).toLocaleString('en-US');

    let panel = null;     // current panel kind
    let data = null;      // current panel data
    let tab = 'person';
    let selected = null;  // selected player id in the menu
    let civOpen = null;   // 'consent' | 'citation' | 'fines'

    // ------------------------------------------------------------------ panel shell
    function open(kind, d, title, sub) {
        panel = kind; data = d;
        $('pTitle').textContent = title;
        $('pSub').textContent = sub || '';
        $('panelWrap').classList.remove('hidden');
    }
    function closePanel(notify = true) {
        $('panelWrap').classList.add('hidden');
        panel = null;
        if (notify) post('close');
    }
    $('pClose').onclick = () => closePanel();

    const act = (name, target) => post('action', { act: name, target });

    // ------------------------------------------------------------------ police menu
    const ICON = { cuff: '⛓', zip: '➰', uncuff: '🔓', escort: '🤝', seat: '🚓', unseat: '🚪', frisk: '✋', search: '🔎', checkid: '🪪',
        breath: '💨', drugtest: '🧪', gsr: '🧤', dna: '🧬', ticket: '📝', arrest: '🏛', comserv: '🧹', unjail: '🗝', runplate: '🔢',
        vehsearch: '🧰', dust: '🖐', impound: '📋', radar: '📡', spikes: '⚠', evidence: '🔦', badge: '⭐', pickup: '⬆', clearprops: '🧺', mdt: '💻' };
    const GROUPS = {
        person: [
            ['Restrain', [['cuff', 'Handcuff'], ['zip', 'Zip-tie'], ['uncuff', 'Remove restraints'], ['escort', 'Escort / let go'], ['seat', 'Put in vehicle'], ['unseat', 'Take out of vehicle']]],
            ['Search & ID', [['frisk', 'Pat down'], ['search', 'Full search'], ['checkid', 'Check ID']]],
            ['Tests', [['breath', 'Breathalyser'], ['drugtest', 'Drug swab'], ['gsr', 'GSR test'], ['dna', 'DNA swab']]],
            ['Justice', [['ticket', 'Write a ticket'], ['arrest', 'Book / jail'], ['comserv', 'Community service'], ['unjail', 'Release sentence']]],
        ],
        vehicle: [
            ['Vehicle', [['runplate', 'Run plate'], ['vehsearch', 'Search vehicle'], ['dust', 'Dust for prints'], ['impound', 'Impound'], ['unseat', 'Take someone out'], ['radar', 'Radar on / off']]],
        ],
    };
    const NEEDS_TARGET = new Set(['cuff', 'zip', 'uncuff', 'escort', 'frisk', 'search', 'checkid', 'breath', 'drugtest', 'gsr', 'dna', 'ticket', 'arrest', 'comserv', 'unjail']);

    function renderMenu() {
        const d = data;
        if (selected && !d.people.some((p) => p.id === selected)) selected = null;
        if (!selected && d.people[0]) selected = d.people[0].id;
        const tabs = [['person', 'Person'], ['vehicle', 'Vehicle'], ['scene', 'Scene'], ['records', 'Records & Evidence']];
        let html = `<div class="tabs">${tabs.map(([k, l]) => `<div class="tab ${tab === k ? 'on' : ''}" data-tab="${k}">${l}</div>`).join('')}</div>`;
        if (tab === 'person') {
            html += `<div class="grid2"><div class="box"><h3>People nearby</h3><div class="people">${d.people.length ? d.people.map((p) => `
                <div class="person ${p.id === selected ? 'on' : ''}" data-id="${p.id}"><span class="pid">${p.id}</span><span class="pn">${esc(p.name)}</span>
                ${p.cuffed ? '<span class="pill red">RESTRAINED</span>' : ''}${p.escorted ? '<span class="pill blue">ESCORTING</span>' : ''}
                <span class="pd">${p.dist}m</span></div>`).join('') : '<div class="empty">Nobody within 6m.</div>'}</div>
                <div style="margin-top:10px"><button class="btn small" data-refresh>↻ Refresh</button></div></div>
                <div class="groups">${groupsHtml(GROUPS.person)}</div></div>`;
        } else if (tab === 'vehicle') {
            html += `<div class="box" style="margin-bottom:12px">${d.vehicle ? `<span class="plate" style="font-size:20px">${esc(d.vehicle.plate)}</span>
                <span style="margin-left:12px;color:var(--text2)">${esc(d.vehicle.model)}</span>` : '<div class="empty">No vehicle right next to you - Run plate still works on the car in front while driving, or type /runplate PLATE.</div>'}</div>
                <div class="groups">${groupsHtml(GROUPS.vehicle)}</div>`;
        } else if (tab === 'scene') {
            html += `<div class="groups">
                <div class="box"><h3>Traffic control</h3><div class="btns">
                    <button class="btn" data-act="spikes"><span class="ic">${ICON.spikes}</span>Spike strip (deploy / pick up)</button>
                    ${d.props.filter((p) => p.key !== 'marker').map((p) => `<button class="btn" data-place="${p.key}"><span class="ic">▲</span>${esc(p.label)}</button>`).join('')}
                </div></div>
                <div class="box"><h3>Crime scene</h3><div class="btns">
                    <button class="btn" data-act="evidence"><span class="ic">${ICON.evidence}</span>Evidence mode on / off</button>
                    <button class="btn" data-place="marker"><span class="ic">①</span>Evidence marker</button>
                </div></div>
                <div class="box"><h3>Tidy up</h3><div class="btns">
                    <button class="btn" data-act="pickup"><span class="ic">${ICON.pickup}</span>Pick up nearest</button>
                    <button class="btn danger" data-act="clearprops"><span class="ic">${ICON.clearprops}</span>Pick up all mine</button>
                    <button class="btn" data-act="badge"><span class="ic">${ICON.badge}</span>Show badge</button>
                </div></div></div>`;
        } else {
            html += `<div class="box"><h3>Mobile data terminal</h3><p style="color:var(--text2);margin-bottom:12px">Look people up, add warrants and notes, see fines and arrests, and send evidence to the lab (at a station).</p>
                <button class="btn primary" data-act="mdt"><span class="ic">${ICON.mdt}</span>Open the MDT</button></div>`;
        }
        $('pBody').innerHTML = html;
    }

    function groupsHtml(groups) {
        return groups.map(([title, list]) => `<div class="box"><h3>${title}</h3><div class="btns">${list.map(([k, l]) =>
            `<button class="btn" data-act="${k}" ${NEEDS_TARGET.has(k) && !selected && tab === 'person' ? 'disabled' : ''}><span class="ic">${ICON[k] || '•'}</span>${l}</button>`).join('')}</div></div>`).join('');
    }

    // ------------------------------------------------------------------ results
    function renderResult() {
        const d = data;
        let h = '';
        if (d.kind === 'breath') {
            h = `<div class="lcd ${d.over ? 'fail' : ''}"><div class="big">${d.bac.toFixed(3)}%</div>
                <div class="sub">${esc(d.name)} · ${d.over ? '<b style="color:#f87171">OVER THE LIMIT</b>' : '<b style="color:#4ade80">UNDER THE LIMIT</b>'} (legal limit ${d.limit.toFixed(2)}%)</div></div>`;
        } else if (d.kind === 'drug') {
            h = `<div class="lcd ${d.positive ? 'fail' : ''}" style="margin-bottom:12px"><div class="big" style="font-size:34px">${d.positive ? 'POSITIVE' : 'NEGATIVE'}</div><div class="sub">${esc(d.name)} · oral fluid screen</div></div>
                <div class="rows">${d.results.map((r) => `<div class="row"><span class="l">${esc(r.label)}</span>${r.positive ? '<span class="pill red">POSITIVE</span>' : '<span class="pill green">NEGATIVE</span>'}</div>`).join('')}</div>`;
        } else if (d.kind === 'gsr') {
            h = `<div class="lcd ${d.positive ? 'fail' : ''}"><div class="big" style="font-size:34px">${d.positive ? 'GSR DETECTED' : 'NO GSR'}</div><div class="sub">${esc(d.name)} · hands swabbed</div></div>`;
        } else if (d.kind === 'dna') {
            h = `<div class="flag green">${esc(d.msg)}</div>`;
        } else if (d.kind === 'frisk' || d.kind === 'search') {
            const full = d.kind === 'search';
            h = `<div class="box" style="margin-bottom:10px"><h3>Weapons</h3>${d.weapons.length ? `<div class="rows">${d.weapons.map((w) =>
                `<div class="row"><span class="l">${esc(w.label)}</span>${full ? `<button class="btn small danger" data-seize="weapon" data-name="${esc(w.name)}">Seize</button>` : ''}</div>`).join('')}</div>`
                : '<div class="empty">No weapons found.</div>'}${!full ? '<p style="color:var(--text3);font-size:12px;margin-top:8px">A pat-down only finds weapons. Do a full search to see everything and seize it.</p>' : ''}</div>`;
            if (full) {
                h += `<div class="box" style="margin-bottom:10px"><h3>Items</h3>${d.items.length ? `<div class="rows">${d.items.map((i) =>
                    `<div class="row"><span class="l">${esc(i.label)} <span style="color:var(--text3)">x${i.count}</span></span>
                    <input type="number" min="1" max="${i.count}" value="${i.count}" data-count="${esc(i.name)}">
                    <button class="btn small danger" data-seize="item" data-name="${esc(i.name)}">Seize</button></div>`).join('')}</div>` : '<div class="empty">Nothing in their bag.</div>'}</div>
                <div class="box"><h3>Cash</h3><div class="row"><span class="l">${money(d.cash)} in cash</span>
                    <input type="number" min="1" value="${d.cash}" data-cashamt><button class="btn small danger" data-seize="cash" ${d.cash > 0 ? '' : 'disabled'}>Seize</button></div></div>`;
            }
        } else if (d.kind === 'vehicle') {
            h = `<div class="box"><h3>Found in vehicle ${esc(d.plate)}</h3>${d.found.length ? `<div class="rows">${d.found.map((f) =>
                `<div class="row"><span class="l">${esc(f.label)}</span><button class="btn small danger" data-vseize="${f.index}">Seize</button></div>`).join('')}</div>` : ''}
                ${d.note ? `<div class="empty">${esc(d.note)}</div>` : ''}</div>`;
        }
        $('pBody').innerHTML = h;
    }

    function renderIdCheck() {
        const d = data;
        const r = d.record;
        let flags = '';
        (r.warrants || []).forEach((w) => { flags += `<div class="flag red">⚠ ACTIVE WARRANT - ${esc(w.reason)} (${esc(w.date)})</div>`; });
        if (r.sentence) flags += `<div class="flag red">Currently serving ${r.sentence === 'jail' ? 'a jail sentence' : 'community service'}</div>`;
        if (r.unpaid > 0) flags += `<div class="flag amber">${r.unpaid} unpaid fine${r.unpaid === 1 ? '' : 's'} - ${money(r.owed)} owed</div>`;
        if (r.arrests > 0) flags += `<div class="flag amber">${r.arrests} previous arrest${r.arrests === 1 ? '' : 's'} / sentence${r.arrests === 1 ? '' : 's'}</div>`;
        if (!flags) flags = '<div class="flag green">No warrants, no unpaid fines.</div>';
        flags += `<div style="margin-top:4px;font-size:12px;color:var(--text3)">DNA on file: ${r.dna ? 'yes' : 'no'} · Prints on file: ${r.prints ? 'yes' : 'no'}</div>`;
        $('pBody').innerHTML = `${idCardHtml(d)}<div class="flags">${flags}</div>`;
    }

    function idCardHtml(d) {
        const photo = d.photo ? `style="background-image:url('https://nui-img/${d.photo}/${d.photo}')"` : '';
        return `<div class="idcard"><div class="photo" ${photo}></div><div class="info"><div class="nm">${esc(d.name)}</div>
            <div class="meta">State ID · Citizen #${d.id}</div>
            <div class="lic">${(d.licences || []).length ? d.licences.map((l) => `<span>${esc(l.label)}</span>`).join('') : '<span style="background:#64748b">No licences</span>'}</div></div></div>`;
    }

    function renderPlate() {
        const d = data;
        $('pBody').innerHTML = `<span class="plate">${esc(d.plate)}</span>
            <div class="kv">${d.model ? `<b>Vehicle</b><span>${esc(d.model)}</span>` : ''}<b>Registered owner</b><span>${esc(d.owner)}</span>
            <b>Registration</b><span>${esc(d.reg)}</span><b>Insurance</b><span>${esc(d.insurance)}</span></div>
            <div class="flags">${d.flags.length ? d.flags.map((f) => `<div class="flag ${/STOLEN|warrant/i.test(f) ? 'red' : 'amber'}">⚠ ${esc(f)}</div>`).join('') : '<div class="flag green">No flags on this vehicle.</div>'}</div>`;
    }

    // ------------------------------------------------------------------ forms
    let picked = new Set();
    function renderForm() {
        const d = data;
        const cats = [];
        d.code.forEach((o, i) => { if (!cats.includes(o.cat)) cats.push(o.cat); });
        let list = '';
        cats.forEach((c) => {
            list += `<div class="cat">${esc(c)}</div>`;
            d.code.forEach((o, i) => {
                if (o.cat !== c) return;
                const extra = [o.fine ? money(o.fine) : '', o.jail ? `${o.jail} min` : ''].filter(Boolean).join(' · ');
                list += `<div class="off ${picked.has(i + 1) ? 'on' : ''}" data-off="${i + 1}"><span>${esc(o.label)}</span><span class="f">${extra}</span></div>`;
            });
        });
        let fine = 0, jail = 0;
        picked.forEach((i) => { fine += d.code[i - 1].fine; jail += d.code[i - 1].jail; });
        jail = Math.min(jail, d.maxJail);
        let totals = '';
        if (panel === 'ticket') {
            totals = `<label>Fine $ <input type="number" id="fAmount" value="${fine}" min="0" style="width:110px"></label>
                <div class="chk">Also revoke: ${['car', 'bike', 'truck', 'firearms'].map((k) => `<label><input type="checkbox" data-revoke="${k}">${k}</label>`).join('')}</div>`;
        } else if (panel === 'arrest') {
            totals = `<label>Jail (minutes) <input type="number" id="fMinutes" value="${Math.max(1, jail)}" min="1" max="${d.maxJail}" style="width:80px"></label>
                <label>Fine $ <input type="number" id="fAmount" value="${fine}" min="0" style="width:110px"></label>
                ${d.cuffed ? '' : '<span class="pill red">They need to be restrained</span>'}`;
        } else {
            const tasks = Math.max(5, Math.min(d.maxTasks, Math.round(jail / 2) || 10));
            totals = `<label>Tasks <input type="number" id="fTasks" value="${tasks}" min="1" max="${d.maxTasks}" style="width:80px"></label>`;
        }
        $('pBody').innerHTML = `<div class="code">${list}</div>
            <div class="totals">${totals}</div>
            <div style="margin-top:10px"><textarea id="fNotes" placeholder="Notes (what happened, location...)"></textarea></div>
            <div style="margin-top:12px;display:flex;gap:8px"><button class="btn primary" data-submit>${panel === 'ticket' ? 'Issue ticket' : panel === 'arrest' ? 'Book into jail' : 'Give community service'}</button>
            <span style="color:var(--text3);font-size:12px;align-self:center">${picked.size} selected</span></div>`;
    }

    function submitForm() {
        if (!picked.size) return;
        const payload = { kind: panel, target: data.target, offences: [...picked], notes: ($('fNotes') || {}).value || '' };
        if ($('fAmount')) payload.amount = Number($('fAmount').value);
        if ($('fMinutes')) payload.minutes = Number($('fMinutes').value);
        if ($('fTasks')) payload.tasks = Number($('fTasks').value);
        payload.revoke = [...document.querySelectorAll('[data-revoke]:checked')].map((c) => c.dataset.revoke);
        panel = null;
        $('panelWrap').classList.add('hidden');
        post('submitForm', payload);
    }

    // ------------------------------------------------------------------ MDT
    let mdt = { results: [], record: null, view: 'people', locker: null };
    function renderMDT() {
        const tabs = `<div class="tabs"><div class="tab ${mdt.view === 'people' ? 'on' : ''}" data-mview="people">People & warrants</div>
            <div class="tab ${mdt.view === 'locker' ? 'on' : ''}" data-mview="locker">Evidence locker & lab</div></div>`;
        if (mdt.view === 'locker') {
            const L = mdt.locker;
            $('pBody').innerHTML = tabs + (L ? `<div class="box"><h3>Evidence (${L.list.length}) ${L.atLab ? '<span class="pill green">AT A LAB</span>' : '<span class="pill amber">GO TO A STATION TO ANALYSE</span>'}</h3>
                <div class="list" style="max-height:470px">${L.list.length ? L.list.map((e) => `<div class="item"><div class="t">${esc(e.id)} · ${esc(e.label)}</div>
                <div class="m">${esc(e.date)} · ${esc(e.officer)}${e.from ? ' · from ' + esc(e.from) : ''}</div>
                ${e.result ? `<div class="r">🔬 ${esc(e.result)}</div>` : ''}
                ${['casing', 'blood', 'prints'].includes(e.type) ? `<div class="inline"><button class="btn small" data-analyse="${esc(e.id)}" ${L.atLab ? '' : 'disabled'}>${e.analysed ? 'Re-analyse' : 'Analyse'}</button></div>` : ''}
                </div>`).join('') : '<div class="empty">The locker is empty.</div>'}</div></div>` : '<div class="empty">Loading...</div>');
            return;
        }
        const left = `<div class="box"><div class="search"><input type="text" id="mQ" placeholder="Name or ID (blank = everyone online)"><button class="btn small primary" data-msearch>Search</button></div>
            <div class="res">${mdt.results.map((r) => `<div class="person ${mdt.record && mdt.record.ident === r.ident ? 'on' : ''}" data-mrec="${esc(r.ident)}">
                ${r.online ? `<span class="pid">${r.online}</span>` : '<span class="pid">off</span>'}<span class="pn">${esc(r.name)}</span>
                ${r.summary.warrants.length ? '<span class="pill red">WARRANT</span>' : ''}${r.summary.unpaid ? '<span class="pill amber">FINES</span>' : ''}</div>`).join('') || '<div class="empty">Search for someone.</div>'}</div></div>`;
        let right = '<div class="box"><div class="empty">Pick someone to see their record.</div></div>';
        const R = mdt.record;
        if (R) {
            const active = R.warrants.filter((w) => w.active);
            right = `<div class="box"><div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap"><h2 style="font-size:19px">${esc(R.name)}</h2>
                ${R.online ? `<span class="pill blue">ONLINE · ID ${R.online}</span>` : '<span class="pill">offline</span>'}
                ${R.dna ? '<span class="pill green">DNA ON FILE</span>' : ''}${R.prints ? '<span class="pill green">PRINTS ON FILE</span>' : ''}
                ${R.sentence ? `<span class="pill red">${R.sentence.kind === 'jail' ? 'IN JAIL' : 'COMMUNITY SERVICE'}</span>` : ''}</div>
                ${R.licences.length ? `<div style="margin-top:6px;color:var(--text2);font-size:12px">Licences: ${R.licences.map(esc).join(', ')}</div>` : ''}
                <h3 style="margin-top:14px">Warrants</h3><div class="list">${R.warrants.length ? R.warrants.map((w) => `<div class="item"><div class="t" style="color:${w.active ? '#fca5a5' : 'var(--text2)'}">${w.active ? '⚠ ACTIVE' : 'Closed'} · ${esc(w.reason)}</div>
                    <div class="m">${esc(w.id)} · ${esc(w.date)} · ${esc(w.officer)}${w.served ? ' · served ' + esc(w.served) : ''}${w.cleared ? ' · cleared ' + esc(w.cleared) : ''}</div>
                    ${w.active ? `<div class="inline"><button class="btn small" data-wclear="${esc(w.id)}">Clear warrant</button></div>` : ''}</div>`).join('') : '<div class="empty">None.</div>'}</div>
                <div class="inline"><input type="text" id="mWarrant" placeholder="New warrant - reason"><button class="btn small danger" data-waddnew>Issue warrant</button></div>
                <h3 style="margin-top:14px">Fines</h3><div class="list">${R.fines.length ? R.fines.map((f) => `<div class="item"><div class="t">${f.paid ? '✔' : '✖'} ${money(f.amount)} · ${esc((f.offences || []).join(', '))}</div>
                    <div class="m">${esc(f.id)} · ${esc(f.date)} · ${esc(f.officer)} · ${f.paid ? (f.waived ? 'waived' : 'paid') : '<b style="color:#fcd34d">UNPAID</b>'}</div>
                    ${!f.paid && R.admin ? `<div class="inline"><button class="btn small" data-waive="${esc(f.id)}">Waive (staff)</button></div>` : ''}</div>`).join('') : '<div class="empty">None.</div>'}</div>
                <h3 style="margin-top:14px">Arrests & sentences</h3><div class="list">${R.arrests.length ? R.arrests.map((a) => `<div class="item"><div class="t">${esc((a.charges || []).join(', '))}</div>
                    <div class="m">${esc(a.id)} · ${esc(a.date)} · ${esc(a.officer)} · ${a.minutes ? a.minutes + ' min jail' : ''}${a.comserv ? a.comserv + ' tasks community service' : ''}${a.fine ? ' · ' + money(a.fine) : ''} · ${esc(a.station || '')}</div>
                    ${a.notes ? `<div class="r">${esc(a.notes)}</div>` : ''}</div>`).join('') : '<div class="empty">None.</div>'}</div>
                <h3 style="margin-top:14px">Notes</h3><div class="list">${R.notes.map((n) => `<div class="item"><div class="t">${esc(n.text)}</div><div class="m">${esc(n.date)} · ${esc(n.officer)}</div></div>`).join('') || '<div class="empty">None.</div>'}</div>
                <div class="inline"><input type="text" id="mNote" placeholder="Add a note"><button class="btn small" data-naddnew>Add note</button></div></div>`;
        }
        $('pBody').innerHTML = tabs + `<div class="mdt">${left}${right}</div>`;
    }

    async function mdtCall(call, a, b, c) {
        const res = await post('mdt', { call, a, b, c });
        if (res && res.ok) {
            if (call === 'mdtSearch') mdt.results = res.results;
            else mdt.record = res;
            renderMDT();
        }
    }

    // ------------------------------------------------------------------ clicks
    $('pBody').addEventListener('click', async (e) => {
        const t = e.target.closest('[data-tab],[data-id],[data-act],[data-place],[data-refresh],[data-seize],[data-vseize],[data-off],[data-submit],[data-mview],[data-msearch],[data-mrec],[data-wclear],[data-waddnew],[data-naddnew],[data-waive],[data-analyse]');
        if (!t || t.disabled) return;
        const ds = t.dataset;
        if (ds.tab) { tab = ds.tab; renderMenu(); }
        else if (ds.id) { selected = Number(ds.id); renderMenu(); }
        else if (ds.refresh !== undefined) { data = await post('refreshMenu'); renderMenu(); }
        else if (ds.act) {
            if (ds.act === 'mdt') { post('action', { act: 'mdt' }); return; }
            act(ds.act, NEEDS_TARGET.has(ds.act) || ds.act === 'seat' ? selected : undefined);
        }
        else if (ds.place) act('place', ds.place);
        else if (ds.seize) {
            const what = ds.seize;
            let count;
            if (what === 'item') count = Number((document.querySelector(`[data-count="${ds.name}"]`) || {}).value || 1);
            if (what === 'cash') count = Number((document.querySelector('[data-cashamt]') || {}).value || 0);
            post('seize', { target: data.id, what, name: ds.name, count });
        }
        else if (ds.vseize) post('vehSeize', { index: Number(ds.vseize) });
        else if (ds.off) { const n = Number(ds.off); picked.has(n) ? picked.delete(n) : picked.add(n); renderForm(); }
        else if (ds.submit !== undefined) submitForm();
        else if (ds.mview) {
            mdt.view = ds.mview;
            if (mdt.view === 'locker') { mdt.locker = null; renderMDT(); const r = await post('locker'); mdt.locker = r && r.ok ? r : { list: [], atLab: false }; }
            renderMDT();
        }
        else if (ds.msearch !== undefined) mdtCall('mdtSearch', $('mQ').value.trim());
        else if (ds.mrec) mdtCall('mdtRecord', ds.mrec);
        else if (ds.wclear) mdtCall('mdtWarrantClear', mdt.record.ident, ds.wclear);
        else if (ds.waddnew !== undefined) { const v = $('mWarrant').value.trim(); if (v) mdtCall('mdtWarrant', mdt.record.ident, v); }
        else if (ds.naddnew !== undefined) { const v = $('mNote').value.trim(); if (v) mdtCall('mdtNote', mdt.record.ident, v); }
        else if (ds.waive) mdtCall('mdtWaive', mdt.record.ident, ds.waive);
        else if (ds.analyse) {
            const res = await post('analyse', { id: ds.analyse });
            if (res && res.ok && mdt.locker) {
                const i = mdt.locker.list.findIndex((x) => x.id === res.item.id);
                if (i >= 0) mdt.locker.list[i] = res.item;
                renderMDT();
            }
        }
    });
    $('pBody').addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && e.target.id === 'mQ') mdtCall('mdtSearch', e.target.value.trim());
    });

    // ------------------------------------------------------------------ civilian popups
    let consentTimer = null;
    function showCiv(kind, html) {
        civOpen = kind;
        $('civ').innerHTML = html;
        $('civWrap').classList.remove('hidden');
    }
    function hideCiv(notify) {
        civOpen = null;
        $('civWrap').classList.add('hidden');
        clearTimeout(consentTimer);
        if (notify) post('closeCiv');
    }

    function ticketHtml(f) {
        return `<div class="ticket"><div class="th"><span>CITATION ${esc(f.id)}</span><span>${esc(f.date)}</span></div>
            ${(f.offences || []).map((o) => `<div>• ${esc(o)}</div>`).join('')}
            ${f.notes ? `<div style="margin-top:6px;font-style:italic">${esc(f.notes)}</div>` : ''}
            ${f.revoked && f.revoked.length ? `<div style="margin-top:6px;color:#b91c1c">Licence revoked: ${f.revoked.map(esc).join(', ')}</div>` : ''}
            <div style="margin-top:6px">Officer: ${esc(f.officer)}</div>
            <div class="tot"><span>TOTAL</span><span>${money(f.amount)}</span></div></div>`;
    }

    $('civ').addEventListener('click', async (e) => {
        const t = e.target.closest('button');
        if (!t) return;
        const ds = t.dataset;
        if (ds.consent) { post('consent', { yes: ds.consent === 'yes' }); hideCiv(false); }
        else if (ds.pay) {
            t.disabled = true;
            const res = await post('payFine', { id: ds.pay, method: ds.method });
            if (res && res.ok) {
                if (civOpen === 'fines' && res.fines) renderFines(res.fines); else hideCiv(true);
            } else t.disabled = false;
        }
        else if (ds.later !== undefined || ds.closeciv !== undefined) hideCiv(true);
    });

    function renderFines(list) {
        const unpaid = list.filter((f) => !f.paid);
        showCiv('fines', `<h2>Your fines</h2><p>${unpaid.length ? `You owe ${money(unpaid.reduce((s, f) => s + f.amount, 0))}. Unpaid fines show up when police check your ID.` : 'You have no unpaid fines.'}</p>
            <div class="list" style="margin-top:12px">${list.length ? list.map((f) => `<div class="item"><div class="t">${f.paid ? '✔' : '✖'} ${money(f.amount)} · ${esc((f.offences || []).join(', '))}</div>
            <div class="m">${esc(f.id)} · ${esc(f.date)} · ${esc(f.officer)}</div>
            ${!f.paid ? `<div class="inline"><button class="btn small primary" data-pay="${esc(f.id)}" data-method="cash">Pay cash</button><button class="btn small" data-pay="${esc(f.id)}" data-method="bank">Pay by card</button></div>` : ''}</div>`).join('') : '<div class="empty">Nothing on record.</div>'}</div>
            <div class="actions"><button class="btn" data-closeciv>Close</button></div>`);
    }

    // ------------------------------------------------------------------ cards & HUDs
    let cardTimer = null;
    function showCard(html) {
        $('card').innerHTML = html;
        $('card').classList.remove('hidden');
        clearTimeout(cardTimer);
        cardTimer = setTimeout(() => $('card').classList.add('hidden'), 9000);
    }

    let progTimer = null;
    function progress(label, ms) {
        $('progLabel').textContent = label;
        const fill = $('progFill');
        fill.style.transition = 'none'; fill.style.width = '0%';
        $('progress').classList.remove('hidden');
        requestAnimationFrame(() => requestAnimationFrame(() => { fill.style.transition = `width ${ms}ms linear`; fill.style.width = '100%'; }));
    }

    function sentenceHud(s) {
        const jail = s.kind === 'jail';
        const v = jail ? `${Math.floor(Math.max(0, s.left) / 60)}:${String(Math.max(0, s.left) % 60).padStart(2, '0')}` : `${s.left} task${s.left === 1 ? '' : 's'}`;
        $('sentence').innerHTML = `<div class="k">${jail ? 'Bolingbroke Penitentiary' : 'Community service'}</div><div class="v">${v}</div>
            <div class="h">${jail ? 'Sweep the yard (marked spots) to cut your time' : 'Sweep the marked spots at Legion Square'}</div>`;
        $('sentence').classList.remove('hidden');
    }

    function radar(m) {
        if (!m.show) { $('radar').classList.add('hidden'); return; }
        $('radar').classList.remove('hidden');
        const d = m.data || {};
        const set = (id, box, v) => {
            const el = $(id);
            el.textContent = v && v.speed != null ? String(v.speed).padStart(3, '0') : '---';
            el.parentElement.classList.toggle('fast', !!(v && v.speed > m.fast));
            $(id + 'Plate').textContent = v ? v.plate : '-';
        };
        set('rFront', 'f', d.front);
        set('rRear', 'r', d.rear);
        $('rPatrol').textContent = d.patrol != null ? String(d.patrol).padStart(3, '0') : '---';
        $('rUnit').textContent = m.unit || 'MPH';
        $('rLock').textContent = m.locked ? 'LOCKED' : '';
    }

    // ------------------------------------------------------------------ messages
    window.addEventListener('message', (ev) => {
        const m = ev.data || {};
        switch (m.action) {
            case 'panel': {
                const d = m.data || {};
                if (m.panel === 'menu') { tab = 'person'; open('menu', d, 'Statewide PD', 'Actions, vehicles, scene and records'); renderMenu(); }
                else if (m.panel === 'result') { open('result', d, { breath: 'Breathalyser', drug: 'Drug swab', gsr: 'Gunshot residue', dna: 'DNA sample', frisk: 'Pat-down', search: 'Search', vehicle: 'Vehicle search' }[d.kind] || 'Result', d.name || d.plate || ''); renderResult(); }
                else if (m.panel === 'idcheck') { open('idcheck', d, 'ID check', `${d.name} · ID ${d.id}`); renderIdCheck(); }
                else if (m.panel === 'plate') { open('plate', d, 'Plate check', 'San Andreas DMV'); renderPlate(); }
                else if (m.panel === 'ticket' || m.panel === 'arrest' || m.panel === 'comserv') {
                    picked = new Set();
                    open(m.panel, d, { ticket: 'Citation', arrest: 'Booking', comserv: 'Community service' }[m.panel], `${d.name} · ID ${d.target}`);
                    renderForm();
                }
                else if (m.panel === 'mdt') { mdt = { results: [], record: null, view: 'people', locker: null }; open('mdt', d, 'Mobile Data Terminal', 'Records · warrants · evidence'); renderMDT(); mdtCall('mdtSearch', ''); }
                break;
            }
            case 'panelUpdate': if (panel === 'result') { data = m.data; renderResult(); } break;
            case 'closePanel': if (!$('panelWrap').classList.contains('hidden')) { $('panelWrap').classList.add('hidden'); panel = null; } break;
            case 'progress': progress(m.label, m.ms); break;
            case 'progressEnd': $('progress').classList.add('hidden'); break;
            case 'consent': {
                showCiv('consent', `<h2>Search request</h2><p><b>${esc(m.officer)}</b> is asking to search you. You can refuse - they'd need to restrain you to search without consent.</p>
                    <div class="actions"><button class="btn primary" data-consent="yes">Allow search</button><button class="btn danger" data-consent="no">Refuse</button></div>
                    <div class="timer"><i id="cTimer"></i></div>`);
                const bar = $('cTimer');
                requestAnimationFrame(() => { bar.style.transition = `width ${m.seconds}s linear`; bar.style.width = '0%'; });
                consentTimer = setTimeout(() => hideCiv(false), m.seconds * 1000);
                break;
            }
            case 'consentClose': if (civOpen === 'consent') hideCiv(false); break;
            case 'citation': {
                const f = m.data;
                showCiv('citation', `<h2>You've been given a ticket</h2><p>Pay now, or later with /fines. Unpaid fines show up when police check your ID.</p>${ticketHtml(f)}
                    <div class="actions">${f.amount > 0 ? `<button class="btn primary" data-pay="${esc(f.id)}" data-method="cash">Pay cash</button><button class="btn" data-pay="${esc(f.id)}" data-method="bank">Pay by card</button>` : ''}<button class="btn" data-later>${f.amount > 0 ? 'Pay later' : 'OK'}</button></div>`);
                break;
            }
            case 'fines': renderFines(m.fines || []); break;
            case 'idCard': showCard(idCardHtml(m.data)); break;
            case 'badgeCard': {
                const b = m.data;
                showCard(`<div class="badgecard"><svg viewBox="0 0 24 24"><path d="M12 2l2.9 5.9 6.5.9-4.7 4.6 1.1 6.5L12 16.8l-5.8 3.1 1.1-6.5L2.6 8.8l6.5-.9z"/></svg>
                    <div><div class="nm">${esc(b.name)}</div><div class="meta">${esc(b.dept)}${b.unit ? ' · Unit ' + esc(b.unit) : ''}</div><div class="meta">Law enforcement officer</div></div></div>`);
                break;
            }
            case 'sentence': sentenceHud(m.data); break;
            case 'sentenceEnd': $('sentence').classList.add('hidden'); break;
            case 'radar': radar(m); break;
        }
    });

    document.addEventListener('keydown', (e) => {
        if (e.key !== 'Escape') return;
        if (civOpen === 'consent') { post('consent', { yes: false }); hideCiv(false); }
        else if (civOpen) hideCiv(true);
        else if (panel) closePanel();
    });
})();
