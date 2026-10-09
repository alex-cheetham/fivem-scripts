// Statewide PD UI: interaction panel, subtitles, radio feed, callout offers, toasts, status chip and the patrol computer
(() => {
    const $ = (id) => document.getElementById(id);
    const RES = window.GetParentResourceName ? window.GetParentResourceName() : 'statewide_police';
    const post = (name, data) => fetch(`https://${RES}/${name}`, { method: 'POST', body: JSON.stringify(data || {}) })
        .then((r) => r.json()).catch(() => ({}));
    const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const money = (n) => '$' + Math.round(n || 0).toLocaleString('en-US');
    const LOGO = 'img/logo.png';
    let BRAND = 'Statewide PD';

    // ================================================================ interaction panel
    let P = null;          // panel data from Lua
    let tab = 'talk';
    let form = null;       // { kind, how, code, maxJail, picked: Set, cat }
    let lastPid = null;

    const QUESTIONS = [
        ['why', 'Why I stopped you', '❔', (d) => d.role === 'driver' || d.role === 'ped' || d.role === 'passenger'],
        ['story', 'What happened here?', '🗨', (d) => d.story],
        ['where', 'Where are you going?', '🧭'],
        ['from', 'Where have you been?', '↩'],
        ['drink', 'Been drinking?', '🍺'],
        ['drugs', 'Taken any drugs?', '💊'],
        ['illegal', 'Anything illegal?', '⚠'],
        ['weapons', 'Any weapons?', '🔪'],
        ['owner', 'Is this your vehicle?', '🚗', (d) => d.hasVeh],
    ];
    const FOLLOW = {
        where: [['where_who', 'Who are you meeting?'], ['where_why', 'What for?']],
        from: [['from_long', 'How long were you there?']],
        drink: [['drink_count', 'How many exactly?'], ['drink_when', 'When was the last one?']],
        drugs: [['drugs_what', 'What did you take?']],
        illegal: [['illegal_again', 'Ask again - last chance']],
        weapons: [['weapons_again', 'Ask again about weapons']],
        owner: [['owner_name', 'Who\'s the registered owner?']],
    };
    const PRESSURE = [
        ['honest', 'Be straight with me', '🤝'],
        ['anything', 'Anything to tell me?', '🫵'],
        ['calm', 'Calm down', '✋', (d) => d.mood === 'hostile' || d.mood === 'nervous' || d.stress > 55],
        ['warrant', 'You have a warrant', '📜', (d) => d.warrant],
        ['leave', 'Leave the property', '🚪', (d) => d.trespass],
    ];

    const MOOD = { calm: ['Calm', 'green'], nervous: ['Nervous', 'amber'], hostile: ['Hostile', 'red'], drunk: ['Intoxicated', 'violet'] };
    const ROLE = { driver: 'Driver', passenger: 'Passenger', ped: 'Pedestrian', suspect: 'Suspect', victim: 'Victim', witness: 'Witness' };

    function chips(d) {
        const c = [];
        const add = (t, k) => c.push(`<span class="chip ${k || ''}">${esc(t)}</span>`);
        if (d.hostage) add('Holding a hostage', 'red');
        if (d.matches) add('Matches BOLO', 'red');
        if (d.inVeh) add(d.isDriver ? 'In driver seat' : 'In vehicle', 'blue');
        if (d.status === 'held' || d.status === 'pulling') add('Detained', 'blue');
        if (d.felony) add('Felony stop', 'red');
        if (d.following) add('Following you', 'blue');
        if (d.status === 'convoy') add('Following your car', 'blue');
        if (d.surrendered) add('Surrendered', 'amber');
        if (d.restrained) add(d.escorted ? 'Cuffed · escorting' : d.seated ? 'Cuffed · in vehicle' : 'Handcuffed', 'red');
        if (d.injured) add('Injured', 'red');
        if (d.pc) add('Probable cause', 'violet');
        if (d.k9) add('K9 indication', 'violet');
        if ((d.lies || []).length) add(`${d.lies.length} lie${d.lies.length === 1 ? '' : 's'} caught`, 'red');
        if (d.noId) add('No ID', 'amber');
        if (d.lang) add(d.interpreter ? `${d.lang} · interpreter` : `Speaks ${d.lang} only`, d.interpreter ? 'blue' : 'amber');
        if (d.knowsYou) add(d.knowsYou.arrests ? `You arrested them ${d.knowsYou.arrests}×` : 'You\'ve stopped them before', 'violet');
        if (d.supervision) add(`On ${d.supervision.kind}`, (d.supervision.violations || []).length ? 'red' : 'amber');
        if (d.child && !d.childCared) add(d.child, 'amber');
        if (d.crisis) add('In crisis', 'violet');
        if (d.voluntary) add('Agreed to get help', 'green');
        if (d.filmed) add('Being filmed', 'red');
        if (d.interfering) add('Interfering', 'red');
        const m = MOOD[d.mood];
        if (m) add(m[0], m[1]);
        return c.join('');
    }

    function meters(d) {
        if (d.role === 'victim' || d.role === 'witness') return '';
        const s = Math.max(0, Math.min(100, d.stress || 0)), r = Math.max(0, Math.min(100, d.rapport || 0));
        return `<div class="ai-meters"><div class="mt"><span>Nervousness</span><div class="bar"><i style="width:${s}%;background:${s > 75 ? '#ef4444' : s > 50 ? '#f59e0b' : '#22c55e'}"></i></div></div>
            <div class="mt"><span>Rapport</span><div class="bar"><i style="width:${r}%;background:#3b82f6"></i></div></div>
            <div class="mt"><span>Fear</span><div class="bar"><i style="width:${Math.max(0, Math.min(100, d.fear || 0))}%;background:#a78bfa"></i></div></div>
            <div class="mt"><span>Anger</span><div class="bar"><i style="width:${Math.max(0, Math.min(100, d.anger || 0))}%;background:#f97316"></i></div></div></div>`;
    }

    function btn(act, label, ic, opts = {}) {
        const data = opts.data ? Object.entries(opts.data).map(([k, v]) => `data-${k}="${esc(v)}"`).join(' ') : '';
        return `<button class="btn ${opts.cls || ''}" data-act="${act}" ${data} ${opts.disabled ? 'disabled' : ''} title="${esc(opts.title || '')}"><span class="ic">${ic}</span>${esc(label)}</button>`;
    }

    function tabsFor(d) {
        if (d.hostage || d.crisis) return [['nego', d.crisis ? 'Talk them down' : 'Negotiate']];
        const t = [['talk', 'Talk'], ['id', 'ID'], ['search', 'Search'], ['orders', 'Orders'], ['end', 'Outcome']];
        if (d.hasVeh && (d.remote || d.felony || d.role === 'driver')) t.splice(4, 0, ['felony', 'Felony']);
        return t;
    }

    function actsHtml(d) {
        let h = '';
        const asked = new Set(d.asked || []);
        if (tab === 'talk') {
            if ((d.cues || []).length) h += `<div class="obs"><b>You notice</b>${d.cues.map((c) => `<span>${esc(c.text)}</span>`).join('')}</div>`;
            if (d.lang && !d.interpreter) {
                h += `<div class="hint warnhint">They only speak ${esc(d.lang)}. Questions, consent and field tests won't work until you get an interpreter on the phone.</div>`;
                h += btn('interpreter', `Call the ${d.lang} language line`, '📞', { cls: 'primary' });
            }
            h += `<div class="tone"><span>Approach</span><div class="seg"><b class="${d.tone !== 'firm' ? 'on' : ''}" data-act="tone" data-tone="calm">😊 Friendly</b><b class="${d.tone === 'firm' ? 'on' : ''}" data-act="tone" data-tone="firm">😠 Firm</b></div></div>`;
            QUESTIONS.forEach(([q, l, ic, show]) => {
                if (show && !show(d)) return;
                h += btn('ask', l, ic, { data: { q }, cls: asked.has(q) ? 'asked' : '' });
                if (asked.has(q) && FOLLOW[q]) FOLLOW[q].forEach(([fq, fl]) => { h += btn('ask', fl, '↳', { data: { q: fq }, cls: 'follow ' + (asked.has(fq) ? 'asked' : '') }); });
            });
            h += '<div class="sep">Pressure & rapport</div>';
            PRESSURE.forEach(([q, l, ic, show]) => { if (!show || show(d)) h += btn('ask', l, ic, { data: { q } }); });
            if ((d.lies || []).length) {
                h += '<div class="sep">Caught lying - confront them</div>';
                d.lies.forEach((l) => {
                    h += `<div class="lie ${l.admitted ? 'adm' : ''}"><span>${esc(l.text)}</span>${l.confronted ? `<em>${l.admitted ? 'Admitted' : 'Denied'}</em>` : `<button class="btn small danger" data-act="confront" data-key="${esc(l.key)}">Confront</button>`}</div>`;
                });
            }
            if ((d.confessed || []).length) {
                h += '<div class="sep">Admissions</div>';
                d.confessed.forEach((c) => { h += `<div class="lie adm"><span>${esc(c)}</span></div>`; });
            }
        } else if (tab === 'id') {
            h += btn('idcard', 'Ask for ID', '🪪', { disabled: d.noId });
            h += btn('idname', 'Ask name & DOB', '🗒');
            h += btn('prints', 'Fingerprint', '🖐', { disabled: !d.restrained, title: 'They need to be restrained' });
            if (d.hasVeh) h += btn('runplate', 'Run the plate', '🔢');
            h += btn('mdt', 'Open MDT', '💻');
            h += `<div class="hint">No ID or giving a false name? Restrain them and fingerprint them to find out who they really are.</div>`;
        } else if (tab === 'search') {
            h += btn('test', 'Pat down', '✋', { data: { kind: 'frisk' } });
            h += btn('test', 'Full search', '🔎', { data: { kind: 'search' } });
            if (d.hasVeh) h += btn('vehsearch', 'Search vehicle', '🧰');
            if (d.hasVeh) h += btn('k9', 'K9 sniff', '🐕');
            h += '<div class="sep">Field sobriety tests</div>';
            const sf = d.sfst || {};
            const mark = (k) => (k in sf) ? (sf[k] ? ' ✗' : ' ✓') : '';
            h += btn('sfst', 'Eye test (HGN)' + mark('hgn'), '👁', { data: { test: 'hgn' } });
            h += btn('sfst', 'Walk and turn' + mark('walk'), '🚶', { data: { test: 'walk' } });
            h += btn('sfst', 'One leg stand' + mark('oneleg'), '🦩', { data: { test: 'oneleg' } });
            h += btn('test', 'Breathalyser', '💨', { data: { kind: 'breath' } });
            h += '<div class="sep">Lab tests</div>';
            h += btn('test', 'Drug swab', '🧪', { data: { kind: 'drug' } });
            h += btn('test', 'GSR test', '🧤', { data: { kind: 'gsr' } });
            h += btn('test', 'DNA swab', '🧬', { data: { kind: 'dna' } });
            h += `<div class="hint">Field tests give you probable cause for a breathalyser and an arrest for DUI - and win the case in court. A full search or vehicle search needs consent, an arrest, a K9 indication or probable cause.</div>`;
        } else if (tab === 'felony') {
            h += `<div class="hint" style="margin-bottom:4px">High-risk stop: stay behind your car with your weapon out and call them out one at a time. Backup will cover you.</div>`;
            h += btn('felony', 'Engine off, keys out', '🔑', { data: { step: 'engine' } });
            h += btn('felony', 'Hands out the windows', '🙌', { data: { step: 'hands' } });
            (d.occupants || []).forEach((o) => {
                h += `<div class="sep">${o.seat === -1 ? 'Driver' : 'Passenger'}${o.label && !/^(Driver|Passenger)$/.test(o.label) ? ' · ' + esc(o.label) : ''}</div>`;
                h += btn('felony', 'Step out, hands up', '🚪', { data: { step: 'exit', pid: o.pid }, disabled: !o.inVeh });
                h += btn('felony', 'Walk back to me', '👣', { data: { step: 'walk', pid: o.pid }, disabled: o.inVeh });
                h += btn('felony', 'On your knees', '🧎', { data: { step: 'kneel', pid: o.pid }, disabled: o.inVeh || o.status === 'surrendered' || o.status === 'cuffed' });
            });
            h += btn('unit', 'Call backup', '🚔', { data: { kind: 'backup' } });
        } else if (tab === 'nego') {
            const n = Math.max(0, Math.min(100, d.nego || 0));
            if (d.crisis) {
                h += `<div class="nego"><div class="nl"><span>Trust</span><b>${n}%</b></div><div class="bar big"><i style="width:${n}%"></i></div>
                    <div class="hint">They're in crisis, not a criminal. Slow down, listen, and give them time. Shouting or rushing in makes it worse. The mental health team (Units) can help.</div></div>`;
                h += btn('nego', 'Listen to them', '👂', { data: { opt: 'listen' } });
                h += btn('nego', 'Breathe with them', '🕊', { data: { opt: 'calm' } });
                h += btn('nego', 'No rush', '⏳', { data: { opt: 'time' } });
                h += btn('nego', 'Offer to call someone', '📞', { data: { opt: 'family' } });
                h += btn('nego', '"You\'re not in trouble"', '🤝', { data: { opt: 'promise' } });
                h += btn('nego', 'Let the clinician talk', '🩺', { data: { opt: 'clinician' }, disabled: !d.clinician, title: d.clinician ? '' : 'Request the mental health team first' });
                h += btn('nego', 'Order them to drop it', '⚠', { data: { opt: 'demand' }, cls: 'danger' });
                return h;
            }
            h += `<div class="nego"><div class="nl"><span>Negotiation</span><b>${n}%</b></div><div class="bar big"><i style="width:${n}%"></i></div>
                <div class="hint">Build trust until they let the hostage go. Push too hard and they'll snap. Don't repeat yourself.</div></div>`;
            h += btn('nego', 'Listen to them', '👂', { data: { opt: 'listen' } });
            h += btn('nego', 'Calm them down', '🕊', { data: { opt: 'calm' } });
            h += btn('nego', 'Give them time', '⏳', { data: { opt: 'time' } });
            h += btn('nego', 'Their family', '👪', { data: { opt: 'family' } });
            h += btn('nego', 'Promise fair treatment', '🤝', { data: { opt: 'promise' } });
            h += btn('nego', 'Demand surrender', '⚠', { data: { opt: 'demand' }, cls: 'danger' });
        } else if (tab === 'orders') {
            if (d.interfere) h += btn('backoff', 'Back off - get back in the car', '✋', { cls: 'warn' });
            if (d.inVeh && !d.restrained) h += btn('out', 'Step out of the vehicle', '🚪');
            if (d.inVeh && d.isDriver && !d.restrained) h += btn('engine', 'Engine off, hands visible', '🔑');
            if (d.inVeh && d.isDriver && !d.restrained) {
                if (d.status === 'convoy') h += btn('convoy', 'Stop here', '🛑', { data: { mode: 'stop' } });
                else { h += btn('convoy', 'Follow my car', '🚓', { data: { mode: 'follow' } }); h += btn('convoy', 'Mimic me', '🪞', { data: { mode: 'mimic' } }); }
            }
            if (!d.inVeh && d.hasVeh && !d.restrained) h += btn('backin', 'Get back in the vehicle', '🚗');
            if (!d.inVeh && !d.restrained) h += btn('follow', d.following ? 'Wait here' : 'Come with me', '👣');
            h += '<div class="sep">Restraints</div>';
            if (!d.restrained) h += btn('cuff', 'Handcuff', '⛓', { disabled: d.inVeh, cls: 'warn' });
            else {
                if (!d.seated) h += btn('escort', d.escorted ? 'Stop escorting' : 'Escort', '🤝');
                if (!d.seated) h += btn('seat', 'Put in vehicle', '🚓');
                if (d.seated || d.inVeh) h += btn('unseat', 'Take out of vehicle', '⬅');
                h += btn('uncuff', 'Remove cuffs', '🔓', { disabled: d.inVeh });
            }
            if (d.partner && !d.partnerDog) {
                h += '<div class="sep">Partner</div>';
                h += btn('partner', 'Watch them', '👁', { data: { cmd: 'watch' } });
                if (!d.restrained) h += btn('partner', 'Partner: pat down', '🖐', { data: { cmd: 'frisk' }, disabled: d.inVeh });
                h += btn('partner', 'Partner: search', '🔍', { data: { cmd: 'search' }, disabled: d.inVeh });
                if (!d.restrained) h += btn('partner', 'Partner: cuff them', '⛓', { data: { cmd: 'cuff' }, disabled: d.inVeh, cls: 'warn' });
                if (d.restrained && !d.seated && !d.escorted) h += btn('partner', 'Partner: put in my car', '🚓', { data: { cmd: 'seat' } });
                if (d.hasVeh) h += btn('partner', 'Partner: run the plate', '🔎', { data: { cmd: 'plate' } });
            }
            if (d.partnerDog) {
                h += '<div class="sep">K9</div>';
                if (d.hasVeh) h += btn('partner', 'Sniff the vehicle', '🐕', { data: { cmd: 'sniff' } });
                if (!d.restrained) h += btn('partner', 'Send the dog (bite)', '⚠', { data: { cmd: 'bite' }, cls: 'danger' });
                h += btn('partner', 'Article search', '🔦', { data: { cmd: 'articles' } });
                h += btn('partner', 'Heel', '↩', { data: { cmd: 'heel' } });
            }
        } else if (tab === 'end') {
            if (d.voluntary) h += btn('hospital', 'Voluntary mental health assessment', '🩺', { cls: 'go' });
            h += btn('warn', 'Verbal warning', '☝', { cls: 'go' });
            h += btn('form', 'Write a citation', '📝', { data: { kind: 'cite' } });
            h += btn('form', d.transport ? 'Hand to transport' : 'Book into custody', '🏛', { data: { kind: 'arrest' }, disabled: !d.canBook, cls: 'warn' });
            h += btn('release', d.restrained ? 'Uncuff & release' : 'Free to go', '👋', { cls: 'go' });
            h += '<div class="sep">Call for</div>';
            h += btn('unit', 'Prisoner transport', '🚐', { data: { kind: 'transport' } });
            if (d.hasVeh) h += btn('unit', 'Tow their vehicle', '🛻', { data: { kind: 'tow' } });
            h += btn('unit', 'Ambulance', '🚑', { data: { kind: 'ems' } });
            h += btn('unit', 'Backup', '🚔', { data: { kind: 'backup' } });
            if (d.child && !d.childCared) {
                h += '<div class="sep">The child</div>';
                h += btn('unit', 'Child & Family Services', '🧸', { data: { kind: 'cps' } });
                h += btn('relative', 'Call a relative to collect them', '📞');
                h += `<div class="hint warnhint">If you arrest the driver, someone has to look after the child. Leaving them is neglect of duty.</div>`;
            }
            if (d.restrained && !d.canBook) h += `<div class="hint">To book them: put them in your car and drive to a station, or call prisoner transport and use “Hand to transport” when it arrives.</div>`;
            if (d.station) h += `<div class="hint">You're at ${esc(d.station)} - you can book them here.</div>`;
        }
        return h;
    }

    function resultHtml(r) {
        if (!r) return '';
        let h = '';
        if (r.kind === 'id') {
            if (r.notFound) {
                h = `<div class="kv" style="margin-top:0"><b>Name given</b><span>${esc(r.name)}</span><b>DOB given</b><span>${esc(r.dob || '-')}</span></div>
                <div class="flags"><div class="flag red">⚠ No record matches these details. They may be lying about who they are - restrain and fingerprint them.</div></div>`;
            } else {
                const photo = r.photo ? `style="background-image:url('https://nui-img/${r.photo}/${r.photo}')"` : '';
                h = `<div class="idcard"><div class="photo" ${photo}></div><div class="info"><div class="nm">${esc(r.name)}</div>
                    <div class="meta">DOB ${esc(r.dob)} · ${r.age} · ${r.gender === 'f' ? 'Female' : 'Male'}</div>
                    <div class="meta">${r.prints ? 'Identified by fingerprints' : r.verbal ? 'Details given verbally' : 'State driving licence'}</div>
                    <div class="lic"><span class="lic-pill lic-${esc(r.licence)}">LICENCE: ${esc(String(r.licence).toUpperCase())}</span></div></div></div>`;
                let f = '';
                (r.warrants || []).forEach((w) => { f += `<div class="flag red">⚠ ACTIVE WARRANT - ${esc(w.reason)}</div>`; });
                if (r.licence !== 'Valid') f += `<div class="flag ${r.licence === 'Suspended' ? 'red' : 'amber'}">Driving licence: ${esc(r.licence)}</div>`;
                (r.flags || []).forEach((x) => { f += `<div class="flag ${/BOLO/.test(x) ? 'red' : 'amber'}">${esc(x)}</div>`; });
                if (r.unpaid > 0) f += `<div class="flag amber">${r.unpaid} unpaid fine${r.unpaid === 1 ? '' : 's'} - ${money(r.owed)}</div>`;
                if (r.arrests > 0) f += `<div class="flag amber">${r.arrests} previous arrest${r.arrests === 1 ? '' : 's'}</div>`;
                if (r.supervision) {
                    f += `<div class="flag ${(r.supervision.violations || []).length ? 'red' : 'amber'}">ON ${esc(r.supervision.kind.toUpperCase())} (${esc(r.supervision.officer || '')}) - ${esc((r.supervision.conditions || []).join(', '))}</div>`;
                    (r.supervision.violations || []).forEach((v) => { f += `<div class="flag red">⚠ VIOLATION: ${esc(v)}</div>`; });
                }
                if (P && P.history) f += `<div class="flag violet">${esc(P.history)}</div>`;
                if (!f) f = '<div class="flag green">No warrants or flags. Clean record.</div>';
                h += `<div class="flags">${f}</div>`;
            }
        } else if (r.kind === 'plate') {
            h = `<span class="plate">${esc(r.plate)}</span><div class="kv"><b>Vehicle</b><span>${esc(r.model || '-')}</span><b>Owner</b><span>${esc(r.owner)}</span>
                <b>Registration</b><span>${esc(r.reg)}</span><b>Insurance</b><span>${esc(r.insurance)}</span></div>
                <div class="flags">${(r.flags || []).length ? r.flags.map((f) => `<div class="flag ${/STOLEN|warrant/i.test(f) ? 'red' : 'amber'}">⚠ ${esc(f)}</div>`).join('') : '<div class="flag green">No flags on this vehicle.</div>'}</div>`;
        } else if (r.kind === 'breath') {
            h = `<div class="lcd ${r.over ? 'fail' : ''}"><div class="big">${Number(r.bac).toFixed(3)}%</div><div class="sub">${r.over ? '<b style="color:#f87171">OVER THE LIMIT</b>' : '<b style="color:#4ade80">UNDER THE LIMIT</b>'} · limit ${Number(r.limit).toFixed(2)}%</div></div>`;
        } else if (r.kind === 'sfst') {
            h = `<div class="sfst ${r.fail ? 'fail' : ''}"><div class="st"><b>${esc(r.title)}</b><span>${r.fail ? 'FAILED' : 'PASSED'}</span></div>
                <div class="dots">${Array.from({ length: r.max }, (_, i) => `<i class="${i < r.count ? 'on' : ''}"></i>`).join('')}<em>${r.count}/${r.max} clues · fail at ${r.failAt}</em></div>
                ${r.clues.length ? `<ul>${r.clues.map((c) => `<li>${esc(c)}</li>`).join('')}</ul>` : '<div class="empty" style="padding:4px 0">No clues observed.</div>'}</div>`;
        } else if (r.kind === 'drug') {
            h = `<div class="lcd ${r.positive ? 'fail' : ''}" style="margin-bottom:8px"><div class="big" style="font-size:28px">${r.positive ? 'POSITIVE' : 'NEGATIVE'}</div><div class="sub">Oral fluid screen</div></div>
                <div class="rows">${r.results.filter((x) => x.positive).map((x) => `<div class="row"><span class="l">${esc(x.label)}</span><span class="pill red">POSITIVE</span></div>`).join('') || ''}</div>`;
        } else if (r.kind === 'gsr') {
            h = `<div class="lcd ${r.positive ? 'fail' : ''}"><div class="big" style="font-size:28px">${r.positive ? 'GSR DETECTED' : 'NO GSR'}</div><div class="sub">Hands swabbed</div></div>`;
        } else if (r.kind === 'dna') {
            h = `<div class="flag green">${esc(r.msg)}</div>`;
        } else if (r.kind === 'person' || r.kind === 'vehicle') {
            const title = r.kind === 'vehicle' ? `Vehicle ${esc(r.plate)}` : (r.full ? 'Full search' : 'Pat down (weapons only)');
            h = `<h3 style="font-size:11px;letter-spacing:.09em;text-transform:uppercase;color:var(--text3);margin-bottom:8px">${title}</h3>`;
            if (!r.items.length) h += `<div class="empty" style="padding:4px 0">Nothing ${r.kind === 'vehicle' ? 'unusual found in the vehicle' : (r.full ? 'of interest found' : 'found - no weapons')}.</div>`;
            else h += `<div class="rows">${r.items.map((it) => `<div class="itm ${it.legal === false || r.kind === 'vehicle' ? 'bad' : ''}"><span class="l">${esc(it.label)}</span>
                ${it.legal === false || r.kind === 'vehicle' ? `<button class="btn small danger" data-act="${r.kind === 'vehicle' ? 'vseize' : 'seize'}" data-index="${it.index}">Seize</button>` : '<span class="pill green">LEGAL</span>'}</div>`).join('')}</div>`;
        }
        return `<div class="rcard"><button class="rx" data-clearres>✕</button>${h}</div>`;
    }

    function formHtml() {
        const f = form;
        const cats = [];
        f.code.forEach((o) => { if (!cats.includes(o.cat)) cats.push(o.cat); });
        if (!f.cat) f.cat = f.kind === 'cite' ? 'Traffic' : 'All';
        let fine = 0, jail = 0;
        f.picked.forEach((i) => { fine += f.code[i - 1].fine; jail += f.code[i - 1].jail; });
        jail = Math.min(Math.max(1, jail), f.maxJail);
        const list = f.code.map((o, i) => (f.cat === 'All' || o.cat === f.cat || f.picked.has(i + 1)) ? `<div class="off ${f.picked.has(i + 1) ? 'on' : ''}" data-off="${i + 1}">
            <span>${esc(o.label)}</span><span class="f">${[o.fine ? money(o.fine) : '', o.jail ? o.jail + ' min' : ''].filter(Boolean).join(' · ')}</span></div>` : '').join('');
        return `<div class="ai-form"><h3>${f.kind === 'cite' ? '📝 Citation' : f.how === 'transport' ? '🚐 Book & hand to transport' : '🏛 Book into custody'}</h3>
            ${f.kind === 'arrest' ? '<div class="hint" style="font-size:12px;color:var(--text3)">Only charge what you can prove - the court checks your evidence for every charge.</div>' : ''}
            <div class="filt">${['All', ...cats].map((c) => `<span class="${f.cat === c ? 'on' : ''}" data-cat="${esc(c)}">${esc(c)}</span>`).join('')}</div>
            <div class="code">${list}</div>
            <div class="tot">Fine <b>${money(fine)}</b>${f.kind === 'arrest' ? ` · Custody <input type="number" id="aiMin" value="${f.minutes ?? jail}" min="1" max="${f.maxJail}" style="width:70px"> min` : ''} · ${f.picked.size} selected</div>
            <textarea id="aiNotes" placeholder="Notes (what happened)">${esc(f.notes || '')}</textarea>
            <div class="row2"><button class="btn" data-formcancel>Cancel</button><button class="btn primary" data-formsubmit ${f.picked.size ? '' : 'disabled'}>${f.kind === 'cite' ? 'Issue citation' : 'Book'}</button></div></div>`;
    }

    function renderPanel() {
        const d = P;
        if (!d) return;
        keepForm();
        const tabs = tabsFor(d);
        if (d.pid !== lastPid) { tab = d.tab && tabs.some((t) => t[0] === d.tab) ? d.tab : tabs[0][0]; lastPid = d.pid; form = null; }
        if (!tabs.some((t) => t[0] === tab)) tab = tabs[0][0];
        const initials = d.known ? d.label.split(' ').map((x) => x[0]).join('').slice(0, 2) : '?';
        const photo = d.result && d.result.photo && d.known ? `style="background-image:url('https://nui-img/${d.result.photo}/${d.result.photo}')"` : '';
        const log = (d.log || []).slice(-30);
        $('aiPanel').innerHTML = `
            <div class="ai-brand"><img src="${LOGO}" alt=""><span>${esc(BRAND)}</span><em>${d.remote ? 'PA / LOUDHAILER' : 'FIELD INTERVIEW'}</em></div>
            <div class="ai-head"><div class="ai-av" ${photo}>${photo ? '' : esc(initials)}</div>
                <div class="ai-ttl"><h2>${esc(d.label)}</h2><p>${esc(ROLE[d.role] || 'Person')}${d.plate ? ' · ' + esc(d.plate) : ''}</p></div>
                <button class="x" data-close>✕</button></div>
            <div class="ai-chips">${chips(d)}</div>
            ${meters(d)}
            <div class="ai-mid" id="aiMid"><div class="ai-log">${log.length ? log.map((l) => `<div class="bub ${l.who === 'you' ? 'you' : 'them'}">${esc(l.text)}</div>`).join('') : '<div class="none">Pick a question below to start talking.</div>'}</div>
            <div class="ai-res">${resultHtml(d.result)}</div></div>
            <div class="ai-tabs">${tabs.map(([k, l]) => `<div class="ai-tab ${tab === k ? 'on' : ''}" data-tab="${k}">${l}</div>`).join('')}</div>
            <div class="ai-acts">${actsHtml(d)}</div>
            <div class="ai-foot"><span>ESC to close · walk away to end</span><span>${esc(d.pid)}</span></div>
            ${form ? formHtml() : ''}`;
        const mid = $('aiMid');
        if (mid) mid.scrollTop = mid.scrollHeight;
        $('aiPanel').classList.remove('hidden');
    }

    function closeAI(notify = true) {
        $('aiPanel').classList.add('hidden');
        form = null;
        P = null;
        if (notify) post('aiClose');
    }

    $('aiPanel').addEventListener('click', (e) => {
        const t = e.target.closest('[data-act],[data-tab],[data-close],[data-off],[data-cat],[data-formcancel],[data-formsubmit],[data-clearres]');
        if (!t) return;
        if (t.dataset.close !== undefined) return closeAI();
        if (t.dataset.tab) { tab = t.dataset.tab; return renderPanel(); }
        if (t.dataset.clearres !== undefined) { if (P) { P.result = null; renderPanel(); } return; }
        if (t.dataset.cat) { keepForm(); form.cat = t.dataset.cat; return renderPanel(); }
        if (t.dataset.off) {
            keepForm();
            const i = Number(t.dataset.off);
            if (form.picked.has(i)) form.picked.delete(i); else form.picked.add(i);
            form.minutes = undefined;
            return renderPanel();
        }
        if (t.dataset.formcancel !== undefined) { form = null; return renderPanel(); }
        if (t.dataset.formsubmit !== undefined) {
            keepForm();
            const payload = { act: form.kind === 'cite' ? 'cite' : 'arrest', offences: [...form.picked], notes: form.notes || '', how: form.how };
            if (form.kind === 'arrest') payload.minutes = Number(form.minutes) || 1;
            form = null;
            renderPanel();
            return post('aiAct', payload);
        }
        if (t.disabled) return;
        const data = { act: t.dataset.act };
        ['q', 'kind', 'test', 'key', 'opt', 'step', 'pid', 'tone', 'mode', 'cmd'].forEach((k) => { if (t.dataset[k] !== undefined) data[k] = t.dataset[k]; });
        if (t.dataset.index) data.index = Number(t.dataset.index);
        if (data.act === 'tone' && P) { P.tone = data.tone; renderPanel(); }
        post('aiAct', data);
    });
    function keepForm() {
        if (!form) return;
        const n = $('aiNotes'); if (n) form.notes = n.value;
        const m = $('aiMin'); if (m) form.minutes = m.value;
    }

    // ================================================================ subtitles, radio, offers, toasts, hud
    let subT = null;
    function subtitle(m) {
        const el = $('aiSubs');
        el.innerHTML = `<b class="${m.me ? 'me' : ''}">${esc(m.name)}:</b> ${esc(m.text)}`;
        el.classList.remove('hidden');
        clearTimeout(subT);
        subT = setTimeout(() => el.classList.add('hidden'), 3500 + Math.min(4000, m.text.length * 45));
    }

    function radio(text) {
        const el = $('aiRadio');
        const line = document.createElement('div');
        line.className = 'rl ' + (/^Dispatch/.test(text) ? 'disp' : /^K9|^Air/.test(text) ? 'unit' : 'me');
        line.innerHTML = `<i>📻</i><span>${esc(text)}</span>`;
        el.appendChild(line);
        while (el.children.length > 4) el.removeChild(el.firstChild);
        el.classList.remove('hidden');
        setTimeout(() => { line.classList.add('fade'); setTimeout(() => line.remove(), 600); }, 9000);
    }

    function toast(m) {
        const el = document.createElement('div');
        el.className = 'toast ' + (m.kind || '');
        el.innerHTML = `<img src="${LOGO}" alt=""><div><b>${esc(m.title)}</b><p>${esc(m.text)}</p>
            ${(m.verdicts || []).length ? `<ul>${m.verdicts.map((v) => `<li class="${v.guilty ? 'g' : 'd'}">${v.guilty ? 'GUILTY' : 'DISMISSED'} · ${esc(v.charge)} <em>${esc(v.why)}</em></li>`).join('')}</ul>` : ''}</div>`;
        $('aiToasts').appendChild(el);
        setTimeout(() => { el.classList.add('fade'); setTimeout(() => el.remove(), 600); }, (m.verdicts || []).length ? 14000 : 7000);
    }

    let offerT = null;
    function offer(o, key) {
        const el = $('aiOffer');
        el.className = o.code === 3 ? '' : 'c2';
        el.innerHTML = `<div class="top"><img src="${LOGO}" alt=""><span class="cbadge">CODE ${o.code}</span><span class="k">${esc(BRAND.toUpperCase())} DISPATCH</span></div>
            <div class="b"><h3>${esc(o.title)}</h3>${o.nature || o.incident ? `<div class="cadline">${o.prio ? `<span class="prio p${o.prio}">P${o.prio}</span>` : ''}${o.nature ? `<span>${esc(o.nature)}</span>` : ''}${o.incident ? `<em>${esc(o.incident)}</em>` : ''}</div>` : ''}
            ${o.where ? `<div class="where">📍 ${esc(o.where)}</div>` : ''}<p>${esc(o.text)}</p>
            <div class="keys"><span><kbd>${esc(key || 'Y')}</kbd>Accept</span><span>Ignore to decline</span></div>
            <div class="timer"><i id="aiOfferT"></i></div></div>`;
        el.classList.remove('hidden');
        const bar = $('aiOfferT');
        bar.style.transition = 'none'; bar.style.width = '100%';
        requestAnimationFrame(() => requestAnimationFrame(() => { bar.style.transition = `width ${o.seconds || 25}s linear`; bar.style.width = '0%'; }));
        clearTimeout(offerT);
        offerT = setTimeout(() => el.classList.add('hidden'), (o.seconds || 25) * 1000 + 500);
    }

    function reachAlert(sec) {
        let el = $('aiReach');
        if (!el) { el = document.createElement('div'); el.id = 'aiReach'; document.body.appendChild(el); }
        el.className = '';
        el.innerHTML = `<b>THEY'RE REACHING FOR SOMETHING</b><span>Aim at them now - or let them</span><div class="timer"><i id="aiReachT"></i></div>`;
        const bar = $('aiReachT');
        bar.style.transition = 'none'; bar.style.width = '100%';
        requestAnimationFrame(() => requestAnimationFrame(() => { bar.style.transition = `width ${sec}s linear`; bar.style.width = '0%'; }));
        setTimeout(() => el.classList.add('hidden'), sec * 1000 + 600);
    }

    let backupT = null;
    function backupReq(o, key) {
        const el = $('aiBackupBox');
        el.className = o.code === 3 ? 'c3' : '';
        el.innerHTML = `<div class="top"><img src="${LOGO}" alt=""><span class="cbadge">CODE ${o.code || 2}</span><span class="k">OFFICER NEEDS ASSISTANCE</span></div>
            <div class="b"><h3>${esc(o.from)} - ${esc(o.label)}</h3><p>📍 ${esc(o.street || 'Their location')} · ${o.dist}m away</p>
            <div class="keys"><span><kbd>${esc(key || 'Y')}</kbd>Respond</span><span>Ignore if you're busy</span></div>
            <div class="timer"><i id="aiBackupT"></i></div></div>`;
        el.classList.remove('hidden');
        const bar = $('aiBackupT');
        bar.style.transition = 'none'; bar.style.width = '100%';
        requestAnimationFrame(() => requestAnimationFrame(() => { bar.style.transition = `width ${o.seconds || 30}s linear`; bar.style.width = '0%'; }));
        clearTimeout(backupT);
        backupT = setTimeout(() => el.classList.add('hidden'), (o.seconds || 30) * 1000 + 500);
    }

    function hud(d) {
        const el = $('aiHud');
        if (!d || !d.on) return el.classList.add('hidden');
        el.className = d.callout ? (d.callout.code === 3 ? 'busy' : 'busy c2') : '';
        el.innerHTML = `<img src="${LOGO}" alt="">` + (d.callout
            ? `<span class="dot"></span>CODE ${d.callout.code} <span class="s">${d.callout.incident ? esc(d.callout.incident) + ' · ' : ''}${esc(d.callout.title)}${d.callout.clear ? ' · scene clear' : d.callout.arrived ? ' · on scene' : ' · en route'}</span>`
            : `<span class="dot"></span>${esc(BRAND.toUpperCase())} <span class="s">available</span>`);
    }

    // ================================================================ patrol computer
    let PC = null;
    let pcTab = 'dispatch';
    let board = null;
    let cad = null;
    function loadCad() {
        post('pcAct', { act: 'cad' }).then((r) => { cad = { list: (r && r.list) || [], busy: !!(r && r.busy) }; if (PC) renderPC(); });
    }
    let openReport = null;
    const drafts = {};
    const UNIT_IC = { backup: '🚔', swat: '🛡', k9: '🐕', partner: '👮', transport: '🚐', roadblock: '🚧', spikes: '📌', ems: '🚑', tow: '🛻', coroner: '⚰️', air: '🚁', crisis: '🩺', cps: '🧸' };
    const UNIT_TXT = { backup: 'Sheriff deputies, code 3. They chase, PIT, fight and cover your stops', swat: 'Armoured team for armed suspects and hostages',
        k9: 'Sniffs vehicles for drugs, tracks and bites runners', partner: 'A deputy (or your dog in K9) who rides with you and takes orders',
        transport: 'Takes your prisoner to jail', roadblock: 'In a pursuit: blocks the road ahead of the suspect', spikes: 'In a pursuit: stop sticks on the road ahead',
        ems: 'Treats the injured', tow: 'Tows the vehicle next to you', coroner: 'Removes bodies from the scene', air: 'Helicopter with a spotlight on your suspect',
        crisis: 'Clinicians for someone in a mental health crisis', cps: 'Looks after children when a parent is arrested' };

    function tiles(s, keys) {
        const k = keys || [['xp', 'Experience'], ['stops', 'Stops'], ['citations', 'Citations'], ['warnings', 'Warnings'], ['arrests', 'Arrests'], ['convictions', 'Convictions'],
            ['dismissed', 'Dismissed'], ['callouts', 'Callouts'], ['cases', 'Cases solved'], ['pursuits', 'Pursuits'], ['seized', 'Items seized'], ['lies', 'Lies caught'], ['reports', 'Reports filed']];
        return `<div class="tiles">${k.map(([key, l]) => `<div class="tile"><b>${Number(s[key] || 0)}</b><span>${l}</span></div>`).join('')}</div>`;
    }

    function rankHtml(r) {
        if (!r) return '';
        const pct = r.nextAt ? Math.min(100, Math.round((r.xp - r.from) / (r.nextAt - r.from) * 100)) : 100;
        return `<div class="rank"><span>RANK</span><b>${esc(r.label)}</b><div class="bar"><i style="width:${pct}%"></i></div>
            <em>${r.nextAt ? `${r.xp} / ${r.nextAt} XP to ${esc(r.nextLabel)}` : `${r.xp} XP · top rank`}</em></div>`;
    }

    function caseHtml(c) {
        return `<div class="pc-card case ${c.solved ? 'solved' : ''}"><div class="ch"><b>${esc(c.id)}</b><span>${esc(c.title)}</span>
            ${c.solved ? '<span class="chip green">Solved</span>' : c.bolo ? '<span class="chip red">BOLO out</span>' : '<span class="chip amber">Open</span>'}
            ${c.warrant ? `<span class="chip ${c.warrant === 'approved' ? 'green' : c.warrant === 'denied' ? 'red' : 'blue'}">Warrant ${esc(c.warrant)}</span>` : ''}
            <em>${esc(c.street || '')} · ${esc(c.created)}</em></div>
            <div class="cg"><div><h4>Suspect description</h4>${c.known.length ? c.known.map((k) => `<div class="kd">${esc(k.text)}</div>`).join('') : '<div class="muted">Nothing yet - talk to the victim and look for evidence.</div>'}</div>
            <div><h4>Evidence</h4>${c.clues.map((cl) => `<div class="kd ${cl.found ? '' : 'muted'}">${cl.found ? '✔ ' + esc(cl.text || cl.label) : '○ ' + esc(cl.label) + ' (not examined)'}</div>`).join('')}</div></div>
            ${c.statements.length ? `<h4>Statements</h4>${c.statements.map((s) => `<div class="stmt"><b>${esc(s.name)}:</b> “${esc(s.text)}”</div>`).join('')}` : ''}
            ${c.solved ? '' : `<div class="btns">
                <button class="btn ${c.canBolo ? 'primary' : ''}" data-pc="bolo" data-id="${esc(c.id)}" ${c.canBolo ? '' : 'disabled'}>📡 Issue BOLO</button>
                <button class="btn" data-pc="warrant" data-id="${esc(c.id)}" ${c.canWarrant ? '' : 'disabled'}>⚖ Apply for warrant</button>
                <button class="btn ${c.warrant === 'approved' ? 'primary' : ''}" data-pc="serve" data-id="${esc(c.id)}" ${c.warrant === 'approved' ? '' : 'disabled'}>🚪 Serve warrant</button></div>`}</div>`;
    }

    function reportHtml(r) {
        if (!r.submitted && !r.court && openReport === r.case) {
            if (drafts[r.case] === undefined) drafts[r.case] = r.text;
            return `<div class="pc-card rep open"><div class="ch"><b>${esc(r.case)}</b><span>${esc(r.name)}</span><span class="chip amber">Draft</span>
                <em>court in ${Math.ceil(r.due / 60)} min without a report</em></div>
                <div class="cg"><div><h4>Charges</h4>${r.charges.map((c) => `<div class="kd">${esc(c)}</div>`).join('')}</div>
                <div><h4>Evidence on file</h4>${r.evidence.length ? r.evidence.map((e) => `<div class="kd">${esc(e)}</div>`).join('') : '<div class="muted">No evidence recorded.</div>'}</div></div>
                <h4>Report <span class="muted" style="text-transform:none;letter-spacing:0">- the timeline is filled in for you. Add what happened in your own words.</span></h4>
                <textarea class="reptxt" id="repTxt" data-case="${esc(r.case)}">${esc(drafts[r.case])}</textarea>
                <div class="btns"><button class="btn" data-pc="repclose">Close</button><button class="btn primary" data-pc="report" data-case="${esc(r.case)}">📨 File report</button></div></div>`;
        }
        let status = '';
        if (r.court) status = `<span class="chip ${r.court.guilty > 0 ? 'green' : 'red'}">${r.court.guilty} guilty · ${r.court.dismissed} dismissed</span>`;
        else if (r.submitted) status = `<span class="chip blue">Filed · court in ${Math.max(1, Math.ceil(r.due / 60))} min</span>`;
        else status = `<span class="chip amber">Report needed</span>`;
        return `<div class="pc-card rep"><div class="ch"><b>${esc(r.case)}</b><span>${esc(r.name)}</span>${status}<em>${esc(r.created)}</em>
            ${!r.submitted && !r.court ? `<button class="btn small primary" data-pc="repopen" data-case="${esc(r.case)}">Write report</button>` : ''}</div>
            <div class="muted" style="font-size:12px;margin-top:4px">${r.charges.map(esc).join(' · ')}</div>
            ${r.court ? `<ul class="verd">${r.court.verdicts.map((v) => `<li class="${v.guilty ? 'g' : 'd'}"><b>${v.guilty ? 'GUILTY' : 'DISMISSED'}</b> ${esc(v.charge)} <em>${esc(v.why)}</em></li>`).join('')}</ul>` : ''}</div>`;
    }

    const iaDrafts = {};
    function conductHtml(c, staff) {
        const good = c.kind === 'commendation';
        const status = good ? '<span class="chip green">Commendation</span>'
            : c.status === 'open' ? `<span class="chip amber">Open · decided in ${Math.max(1, Math.ceil((c.due || 0) / 60))} min</span>`
            : `<span class="chip ${c.outcome === 'sustained' ? 'red' : 'green'}">${esc((c.outcome || '').toUpperCase())}</span>`;
        let h = `<div class="pc-card rep ia"><div class="ch"><b>${esc(c.id)}</b><span>${esc(good ? c.text : c.kind)}</span>${status}<em>${esc(c.date || '')}${staff ? ' · ' + esc(c.officer || '') : ''}</em></div>`;
        if (!good) h += `<div class="muted" style="font-size:12.5px;margin-top:4px">${esc(c.text)}${c.person ? ' - ' + esc(c.person) : ''}${(c.evidence || []).length ? ' · Evidence: ' + c.evidence.map(esc).join(', ') : ''}</div>`;
        if (!good && !staff && c.status === 'open') {
            if (c.response) h += `<div class="stmt"><b>Your statement:</b> ${esc(c.response)}</div>`;
            else h += `<textarea class="reptxt iatxt" data-ia="${esc(c.id)}" placeholder="Your account of what happened (at least a couple of sentences)...">${esc(iaDrafts[c.id] || '')}</textarea>
                <div class="btns"><button class="btn primary" data-pc="iaRespond" data-id="${esc(c.id)}">Submit statement</button></div>`;
        }
        if (staff && c.status === 'open' && !good) {
            h += `<div class="btns"><button class="btn danger small" data-pc="iaDecide" data-id="${esc(c.id)}" data-outcome="sustained">Sustain</button>
                <button class="btn small" data-pc="iaDecide" data-id="${esc(c.id)}" data-outcome="not sustained">Not sustained</button>
                <button class="btn small" data-pc="iaDecide" data-id="${esc(c.id)}" data-outcome="exonerated">Exonerate</button></div>`;
        }
        return h + '</div>';
    }

    function renderPC() {
        const d = PC;
        if (!d) return;
        BRAND = d.brand || BRAND;
        const pending = (d.reports || []).filter((r) => !r.submitted && !r.court).length;
        const openCases = (d.cases || []).filter((c) => !c.solved).length;
        const nav = [['dispatch', '📡', 'Dispatch'], ['cad', '🗺', 'CAD board', cad ? cad.list.filter((b) => b.status === 'pending').length : 0], ['radio', '📻', 'Radio'], ['units', '🚔', 'Units'], ['cases', '🗂', 'Cases', openCases],
            ['reports', '📝', 'Reports & court', pending], ['conduct', '⚖', 'Conduct', ((d.ia || {}).mine || []).filter((c) => c.status === 'open').length], ['stats', '📊', 'My stats'],
            ['board', '🏆', 'Leaderboard']].concat(d.places && d.places.admin ? [['places', '📍', 'Places']] : []).concat([['help', '⌨', 'How it works']]);
        let body = '';
        if (pcTab === 'dispatch') {
            const c = d.callout;
            const st = !d.on ? ['off', '⏻', 'Off patrol', 'Switch AI patrol on to get callouts from dispatch.']
                : d.paused ? ['busy', '⏸', '10-6 · Busy', 'Dispatch is holding your calls. Go 10-8 on the Radio tab when you\'re free.']
                : c ? ['busy', '🚨', 'On a callout', c.clear ? 'Scene clear - finish up and press Code 4.' : c.arrived ? 'On scene.' : 'Responding.']
                : d.busy ? ['busy', '🚓', 'Busy', 'Dealing with a stop.']
                : ['', '📻', 'Available', d.nextIn != null ? `Next callout in about ${Math.max(5, Math.ceil(d.nextIn / 5) * 5)}s.` : 'Waiting for dispatch...'];
            body += `<div class="pc-card"><div class="pc-status"><div class="ring ${st[0]}">${st[1]}</div><div><div class="big">${st[2]}</div><div class="sub">${esc(st[3])}</div></div></div></div>`;
            if (c) {
                body += `<div class="pc-card call ${c.code === 3 ? '' : 'c2'}"><div class="ct"><span class="badge">CODE ${c.code}</span><b>${esc(c.title)}</b></div>
                    ${c.nature || c.incident ? `<div class="cadline">${c.prio ? `<span class="prio p${c.prio}">P${c.prio}</span>` : ''}${c.nature ? `<span>${esc(c.nature)}</span>` : ''}${c.incident ? `<em>${esc(c.incident)}</em>` : ''}</div>` : ''}
                    <p>${esc(c.text)}</p>
                    ${(c.notes || []).length ? `<div class="cadnotes">${c.notes.map((n) => `<div><em>${esc(n.t)}</em>${esc(n.text)}</div>`).join('')}</div>` : ''}<div class="meta"><span>📍 ${esc(c.street)}</span><span>⏱ ${c.minutes} min</span><span>${c.clear ? '✅ Scene clear' : c.arrived ? '🟡 On scene' : '🔴 En route'}</span></div>
                    ${c.people.length ? `<div class="ppl">${c.people.map((p) => `<span class="chip ${p.role === 'suspect' ? 'red' : p.role === 'victim' ? 'amber' : 'blue'}">${esc(p.name || p.role)} · ${esc(p.status)}</span>`).join('')}</div>` : ''}
                    <div class="btns"><button class="btn" data-pc="route">🧭 Set route</button><button class="btn ${c.clear ? 'primary' : ''}" data-pc="code4">✅ Code 4 (close)</button></div></div>`;
            }
            if (pending) body += `<div class="pc-card alert" data-pctab="reports">📝 You have ${pending} arrest report${pending === 1 ? '' : 's'} to write. Cases without a report are weaker in court. <b>Open reports →</b></div>`;
            body += `<div class="pc-card"><h3>Shift log</h3><div class="plog">${(d.log || []).length ? d.log.map((l) => `<div><em>${esc(l.t)}</em>${esc(l.text)}</div>`).join('') : '<div style="color:var(--text3)">Nothing yet this shift.</div>'}</div></div>`;
        } else if (pcTab === 'cad') {
            if (!cad) { loadCad(); body += '<div class="pc-card">Loading the board...</div>'; }
            else {
                const ST = { pending: ['red', 'PENDING'], offered: ['amber', 'OFFERED'], enroute: ['blue', 'EN ROUTE'], onscene: ['amber', 'ON SCENE'], closed: ['green', 'CLOSED'] };
                body += `<div class="pc-card"><h3>County calls <button class="btn small" style="float:right" data-pc="cadRefresh">↻ Refresh</button></h3>
                    <div class="muted" style="font-size:12px;margin-bottom:8px">Every call in the county. Pending calls are waiting for a unit - take one yourself with <b>Self-assign</b>, or another unit will pick it up.</div>
                    ${cad.list.length ? `<table class="cad"><tr><th>Incident</th><th>P</th><th>Nature</th><th>Area</th><th>Age</th><th>Status</th><th></th></tr>
                    ${cad.list.map((b) => `<tr class="${b.mine ? 'mine' : ''} ${b.status}"><td><b>${esc(b.id)}</b></td><td><span class="prio p${b.prio || 3}">P${b.prio || 3}</span></td>
                        <td><b>${esc(b.title)}</b><br><span class="muted">${esc(b.nature || '')}</span></td><td>${esc(b.area || '')}</td><td>${b.age}m</td>
                        <td><span class="chip ${(ST[b.status] || ST.pending)[0]}">${(ST[b.status] || ST.pending)[1]}</span>${b.unit ? `<br><span class="muted">${esc(b.unit)}</span>` : ''}${b.disposition ? `<br><span class="muted">${esc(b.disposition)}</span>` : ''}</td>
                        <td>${b.status === 'pending' ? `<button class="btn small primary" data-pc="cadTake" data-id="${esc(b.id)}" ${cad.busy ? 'disabled' : ''}>Self-assign</button>` : ''}</td></tr>`).join('')}</table>`
                    : '<div class="muted">The board is quiet. Calls appear here while anyone is on AI patrol.</div>'}</div>`;
            }
        } else if (pcTab === 'radio') {
            body += `<div class="pc-card"><h3>Status - ${esc(d.callsign)}</h3><div class="codes">
                <button class="btn ${!d.paused ? 'primary' : ''}" data-pc="pause" data-on="0">10-8 In service</button>
                <button class="btn ${d.paused ? 'warn' : ''}" data-pc="pause" data-on="1">10-6 Busy</button>
                <button class="btn" data-pc="status" data-code="10-97">10-97 En route</button>
                <button class="btn" data-pc="status" data-code="10-23">10-23 On scene</button>
                <button class="btn" data-pc="status" data-code="10-15">10-15 Prisoner</button>
                <button class="btn" data-pc="status" data-code="code4">Code 4</button>
                <button class="btn" data-pc="runplate">10-28 Run plate</button>
                <button class="btn" data-pc="mdt">10-29 Check person</button></div></div>
                <div class="pc-card"><h3>Radio traffic</h3><div class="plog radiolog">${(d.radio || []).slice().reverse().map((l) => `<div><em>${esc(l.t)}</em>${esc(l.text)}</div>`).join('') || '<div style="color:var(--text3)">Quiet so far.</div>'}</div></div>`;
        } else if (pcTab === 'units') {
            body += `<div class="pc-card"><h3>Request a unit</h3><div class="pc-units">${d.unitsCfg.map((u) => `<button class="unit" data-pc="unit" data-kind="${u.kind}">
                <div class="ui">${UNIT_IC[u.kind] || '🚓'}</div><b>${esc(u.label)}</b><span>${esc(UNIT_TXT[u.kind] || '')}</span></button>`).join('')}</div></div>`;
            if (d.pursuit) {
                body = `<div class="pc-card pursuit-card"><h3>🚨 Pursuit${d.pursuit.terminated ? ' (terminated)' : ''}</h3><div class="muted" style="font-size:13px">${d.pursuit.minutes} min · ${d.pursuit.units} unit${d.pursuit.units === 1 ? '' : 's'} with you · ${esc(d.pursuit.street)}</div>
                    <div class="btns" style="margin-top:10px"><button class="btn" data-pc="unit" data-kind="spikes">📌 Spike strips ahead</button><button class="btn" data-pc="unit" data-kind="roadblock">🚧 Roadblock ahead</button>
                    <button class="btn" data-pc="unit" data-kind="air">🚁 Air unit</button>${d.pursuit.terminated ? '' : '<button class="btn danger" data-pc="terminate">Terminate pursuit</button>'}</div></div>` + body;
            }
            body += `<div class="pc-card"><h3>Units with you</h3>${d.units.length ? `<div>${d.units.map((u) => `<div class="unit-row">${UNIT_IC[u.kind] || ''} ${esc(u.label)} ${u.dist ? `<span class="cnt">${u.dist}m</span>` : ''}<em>${esc(u.state)}</em></div>`).join('')}</div>
                <div class="btns" style="margin-top:10px"><button class="btn danger" data-pc="dismiss">Dismiss all units</button></div>` : '<div style="color:var(--text3);font-size:13px">No units requested.</div>'}</div>`;
            if (d.partner) {
                body += `<div class="pc-card"><h3>${d.partnerDog ? '🐕 K9 partner' : '👮 Partner'}</h3><div class="btns">${d.partnerDog
                    ? '<button class="btn" data-pc="partnerCmd" data-cmd="track">🐾 Track the suspect</button><button class="btn" data-pc="partnerCmd" data-cmd="articles">🔦 Article search</button><button class="btn" data-pc="partnerCmd" data-cmd="heel">↩ Heel</button>'
                    : '<button class="btn" data-pc="partnerCmd" data-cmd="heel">↩ Back to me</button>'}
                    <button class="btn danger" data-pc="dismiss" data-kind="partner">Send home</button></div>
                    <div class="muted" style="font-size:12px;margin-top:8px">Give orders about a person from their stop menu (Orders tab).</div></div>`;
            }
            body += `<div class="pc-card"><h3>Division</h3><div class="muted" style="font-size:12px;margin-bottom:8px">You get more of the callouts that suit your division. K9 gives you a dog as your partner.</div>
                <div class="divs">${(d.divisions || []).map((v) => `<button class="btn ${d.division === v.key ? 'primary' : ''}" data-pc="division" data-key="${esc(v.key)}" data-label="${esc(v.label)}">${esc(v.label)}</button>`).join('')}</div></div>`;
            if (d.admin) {
                body += `<div class="pc-card"><h3>Unit uniforms <span class="chip amber" style="margin-left:6px">Staff</span></h3>
                    <div class="muted" style="font-size:12px;margin-bottom:6px">Put the outfit on (any clothing menu), then press <b>Save what I'm wearing</b> for that unit. Save a few (male and female) and units pick one at random. Units with nothing saved use the "All units" uniform, then the default sheriff peds.</div>
                    ${(d.uniforms || []).map((u) => `<div class="unit-row">${UNIT_IC[u.slot] || '👕'} ${esc(u.label)} <span class="cnt">${u.count ? u.count + ' saved' : 'default'}</span>
                        <div class="uni-btns"><button class="btn small primary" data-pc="uniformSave" data-slot="${u.slot}">Save what I'm wearing</button>
                        <button class="btn small" data-pc="uniformPreview" data-slot="${u.slot}">Preview</button>
                        <button class="btn small" data-pc="uniformReset" data-slot="${u.slot}" ${u.count ? '' : 'disabled'}>Clear</button></div></div>`).join('')}</div>`;
            }
        } else if (pcTab === 'cases') {
            body += (d.cases || []).length ? d.cases.map(caseHtml).join('') : `<div class="pc-card"><h3>Investigations</h3><div class="muted">No cases yet. Burglary, assault, vehicle theft and store robbery callouts open a case file here: take statements, examine evidence, issue a BOLO or get a warrant.</div></div>`;
        } else if (pcTab === 'reports') {
            if (!openReport) body += `<div class="pc-card"><h3>How court works</h3><div class="muted" style="font-size:13px;line-height:1.5">Every charge is checked against your evidence: breath and field tests for DUI, seized drugs for possession, a recovered weapon for firearm charges, fleeing for evading... A filed report, admissions and caught lies make cases stronger. Unsupported charges get dismissed.</div></div>`;
            body += (d.reports || []).length ? d.reports.map(reportHtml).join('') : '<div class="pc-card"><div class="muted">No arrests yet this session.</div></div>';
        } else if (pcTab === 'conduct') {
            const ia = d.ia || { mine: [] };
            body += `<div class="pc-card"><h3>Your conduct</h3><div class="tiles"><div class="tile"><b>${ia.commendations || 0}</b><span>Commendations</span></div>
                <div class="tile"><b>${ia.sustained || 0}</b><span>Sustained complaints</span></div><div class="tile"><b>${(ia.mine || []).filter((c) => c.status === 'open').length}</b><span>Open complaints</span></div></div>
                <div class="muted" style="font-size:12px;margin-top:8px">Complaints come from force on people who weren't a threat, searches without consent or cause, rudeness, wrongful arrests and leaving children alone. Bystander video makes them stick. Answer open complaints with your account before Internal Affairs decide.</div></div>`;
            body += (ia.mine || []).length ? ia.mine.map((c) => conductHtml(c, false)).join('') : '<div class="pc-card"><div class="muted">No complaints or commendations yet.</div></div>';
            if (ia.admin && (ia.all || []).length) {
                body += `<div class="pc-card"><h3>All officers <span class="chip amber" style="margin-left:6px">Staff</span></h3>${ia.all.map((c) => conductHtml(c, true)).join('')}</div>`;
            }
        } else if (pcTab === 'places') {
            const pl = d.places || { types: [], nearby: [] };
            body += `<div class="pc-card"><h3>Add a place <span class="chip amber" style="margin-left:6px">Staff</span></h3>
                <div class="muted" style="font-size:12px;margin-bottom:8px">Stand where it should happen (for stores: behind the counter, facing the customers), pick the type and save. Shops, gas stations and empty houses are added automatically from your other scripts.</div>
                <div class="placeform"><select id="plType">${pl.types.filter((t) => !t.auto).map((t) => `<option value="${esc(t.key)}">${esc(t.label)}</option>`).join('')}</select>
                <input id="plLabel" maxlength="40" placeholder="Name (e.g. Yellow Jack Inn)"><button class="btn primary" data-pc="placeAdd">Save here</button></div></div>`;
            body += `<div class="pc-card"><h3>Places by type</h3>${pl.types.map((t) => `<div class="unit-row">${esc(t.label)}<em>${t.count}</em></div>`).join('')}</div>`;
            body += `<div class="pc-card"><h3>Near you</h3>${pl.nearby.length ? pl.nearby.map((p) => `<div class="unit-row"><b style="min-width:70px">${esc(p.type)}</b> ${esc(p.label)} <span class="cnt">${p.dist}m</span>
                ${p.staff ? `<div class="uni-btns"><button class="btn small" data-pc="placeRemove" data-id="${esc(p.id)}">Remove</button></div>` : ''}</div>`).join('') : '<div class="muted">No places within 600m.</div>'}</div>`;
        } else if (pcTab === 'stats') {
            body += `<div class="pc-card"><h3>This shift</h3>${tiles(d.shift || {})}</div><div class="pc-card"><h3>All time</h3>${tiles(d.total || {})}</div>`;
        } else if (pcTab === 'board') {
            if (!board) { post('pcAct', { act: 'board' }).then((r) => { board = (r && r.list) || []; renderPC(); }); body += '<div class="pc-card">Loading...</div>'; }
            else body += `<div class="pc-card"><h3>Top officers</h3>${board.length ? `<table class="board"><tr><th>#</th><th>Officer</th><th>Arrests</th><th>Citations</th><th>Callouts</th><th>Stops</th></tr>
                ${board.map((b, i) => `<tr class="${i === 0 ? 'top1' : ''}"><td>${i + 1}</td><td>${esc(b.name)}</td><td>${b.arrests}</td><td>${b.citations}</td><td>${b.callouts}</td><td>${b.stops}</td></tr>`).join('')}</table>` : '<div style="color:var(--text3)">No stats yet.</div>'}</div>`;
        } else {
            const k = d.keys || {};
            body += `<div class="pc-card"><h3>Keys</h3><div class="keys">
                <kbd>${esc(k.computer)}</kbd><span>Patrol computer (this screen)</span>
                <kbd>${esc(k.stop)}</kbd><span>In a police car with lights on: pull over the vehicle in front</span>
                <kbd>${esc(k.interact)}</kbd><span>Tap next to someone you've stopped to talk. Hold next to anyone on foot to stop them. Tap near a stopped car (up to 35m) for felony stop orders, or near a hostage taker to negotiate. Tap on evidence to bag it</span>
                <kbd>${esc(k.interact)}</kbd><span>While sprinting at a runner: tackle</span>
                <kbd>${esc(k.accept)}</kbd><span>Accept a callout when it pops up</span></div></div>
                <div class="pc-card"><h3>How it works</h3><div style="color:var(--text2);font-size:13px;line-height:1.6">
                Switch <b>AI patrol</b> on and dispatch sends you callouts. Between callouts you'll see things happen in front of you (on-view incidents).
                People have moods, stories and secrets. Watch their <b>nervousness</b> - pressure (Firm) makes guilty people slip up but also makes them run; building <b>rapport</b> (Friendly) gets confessions.
                Catch lies with evidence (breath tests, searches, plates, the passenger's story) and <b>confront</b> them. Use field sobriety tests, K9 and searches to build probable cause.
                Runners throw away evidence and hide - search for them, or use K9 / the air unit. Every arrest needs a <b>report</b>, and court decides each charge on your evidence.
                Investigations live in the <b>Cases</b> tab: statements, evidence, BOLOs and warrants. You earn XP and rank up.</div></div>`;
        }
        if (!nav.some((n) => n[0] === pcTab)) { pcTab = 'dispatch'; return renderPC(); }
        $('pc').innerHTML = `<div class="pc"><div class="pc-side"><div class="pc-brand"><img src="${LOGO}" alt=""><div><b>${esc(BRAND)}</b><span>Patrol Computer</span></div></div>
            ${rankHtml(d.rank)}
            ${nav.map(([k, ic, l, n]) => `<div class="pc-nav ${pcTab === k ? 'on' : ''}" data-pctab="${k}"><span>${ic}</span>${l}${n ? `<i class="cnt">${n}</i>` : ''}</div>`).join('')}
            <div class="grow"></div><div class="where">📻 ${esc(d.callsign)}<br>📍 ${esc(d.street)}</div></div>
            <div class="pc-main"><div class="pc-top"><h1>${nav.find((n) => n[0] === pcTab)[2]}</h1>
            <div class="tog ${d.on ? 'on' : ''}" data-pc="toggle"><span class="sw"></span>AI PATROL ${d.on ? 'ON' : 'OFF'}</div>
            <button class="x" data-pcclose>✕</button></div><div class="pc-body">${body}</div></div></div>`;
        $('pc').classList.remove('hidden');
    }

    function closePC(notify = true) {
        $('pc').classList.add('hidden');
        PC = null;
        if (notify) post('pcClose');
    }

    $('pc').addEventListener('input', (e) => {
        if (e.target.id === 'repTxt') drafts[e.target.dataset.case] = e.target.value;
        if (e.target.dataset && e.target.dataset.ia) iaDrafts[e.target.dataset.ia] = e.target.value;
    });
    $('pc').addEventListener('click', (e) => {
        const t = e.target.closest('[data-pc],[data-pctab],[data-pcclose]');
        if (!t) { if (e.target.id === 'pc') closePC(); return; }
        if (t.dataset.pcclose !== undefined) return closePC();
        if (t.dataset.pctab) { pcTab = t.dataset.pctab; if (pcTab === 'board') board = null; if (pcTab === 'cad') cad = null; return renderPC(); }
        const act = t.dataset.pc;
        if (t.disabled) return;
        if (act === 'repopen') { openReport = t.dataset.case; return renderPC(); }
        if (act === 'cadRefresh') { cad = null; return renderPC(); }
        if (act === 'cadTake') {
            t.disabled = true;
            return post('pcAct', { act, id: t.dataset.id }).then((r) => { if (r && r.ok) { cad = null; closePC(false); } else { cad = null; renderPC(); } });
        }
        if (act === 'repclose') { openReport = null; return renderPC(); }
        if (act === 'iaRespond') return post('pcAct', { act, id: t.dataset.id, text: iaDrafts[t.dataset.id] || '' });
        if (act === 'iaDecide') return post('pcAct', { act, id: t.dataset.id, outcome: t.dataset.outcome });
        if (act === 'placeAdd') return post('pcAct', { act, kind: ($('plType') || {}).value, label: ($('plLabel') || {}).value || '' });
        if (act === 'placeRemove') return post('pcAct', { act, id: t.dataset.id });
        if (act === 'report') {
            const text = drafts[t.dataset.case] || '';
            openReport = null;
            return post('pcAct', { act, case: t.dataset.case, text });
        }
        if (act === 'unit' || act === 'mdt' || act === 'runplate' || act === 'partnerCmd' || act === 'uniformPreview') closePC(false);
        post('pcAct', { act, kind: t.dataset.kind, id: t.dataset.id, code: t.dataset.code, on: t.dataset.on === '1',
            key: t.dataset.key, label: t.dataset.label, slot: t.dataset.slot, cmd: t.dataset.cmd });
    });

    // ================================================================ messages
    window.addEventListener('message', (ev) => {
        const m = ev.data || {};
        switch (m.action) {
            case 'aiPanel': P = m.data; renderPanel(); break;
            case 'aiPanelClose': closeAI(false); break;
            case 'aiForm': if (P) { form = { kind: m.kind, how: m.how, code: m.code || [], maxJail: m.maxJail || 120, picked: new Set(), cat: null }; renderPanel(); } break;
            case 'aiSay': subtitle(m); break;
            case 'aiRadio': radio(m.text); break;
            case 'aiToast': toast(m); break;
            case 'aiOffer': offer(m.data, m.key); break;
            case 'aiOfferGone': clearTimeout(offerT); $('aiOffer').classList.add('hidden'); break;
            case 'aiBackup': backupReq(m.data, m.key); break;
            case 'aiReach': reachAlert(m.seconds || 2); break;
            case 'aiReachDone': { const r = $('aiReach'); if (r) r.classList.add('hidden'); break; }
            case 'aiBackupGone': clearTimeout(backupT); $('aiBackupBox').classList.add('hidden'); break;
            case 'aiHud': hud(m.data); break;
            case 'pcOpen': PC = m.data; if (!m.update) { pcTab = PC.callout ? 'dispatch' : pcTab; cad = null; } renderPC(); break;
            case 'pcClose': closePC(false); break;
        }
    });

    document.addEventListener('keydown', (e) => {
        if (e.key !== 'Escape') return;
        if (P && form) { form = null; renderPanel(); return; }
        if (P) closeAI();
        else if (PC) closePC();
    });
})();
