$(function () {
    let currentTab = 0;
    let currentBtn = 0;
    let selectedPlayerId = null;
    let selectedPlayerName = "";
    // track last active tab so we can detect tab switches
    let lastTab = null;
    let availableWeathers = [];
    let availableTimes = [];
    let allPlayers = [];
    let lastPlayersFetch = 0;
    let uiLocales = {};
    let uiIsGod = false;
    let pendingAction = null;
    let allItems = [];
    let allBans = [];
    const tabs = ['admin', 'player', 'world', 'server'];

    function translateUI() {
        $('[data-i18n]').each(function() {
            const key = $(this).data('i18n');
            if (uiLocales[key]) $(this).text(uiLocales[key]);
        });
        $('[data-i18n-placeholder]').each(function() {
            const key = $(this).data('i18n-placeholder');
            if (uiLocales[key]) $(this).attr('placeholder', uiLocales[key]);
        });
    }

    function applySettings(config) {
        if (!config) return;

        // Colors
        if (config.colors) {
            const root = document.documentElement;
            root.style.setProperty('--primary', config.colors.primary);
            root.style.setProperty('--secondary', config.colors.secondary);
            root.style.setProperty('--danger', config.colors.danger);
            root.style.setProperty('--success', config.colors.success || '#2ecc71');
            root.style.setProperty('--warning', config.colors.warning || '#f1c40f');
        }

        // Position & Transparency
        const wrapper = $("#adminMenu");
        if (config.position === 'left') {
            wrapper.css({ 'right': 'auto', 'left': '20px' });
        } else {
            wrapper.css({ 'left': 'auto', 'right': '20px' });
        }

        const bgColor = config.colors ? hexToRgb(config.colors.secondary) : "0,0,0";
        wrapper.css('background', `rgba(${bgColor}, ${config.transparency || 0.95})`);

        // Logo Text
        if (config.logo) {
            $(".logo").html(`${config.logo.main}<span>${config.logo.sub}</span>`);
        }

        // Fade Speed
        window.uiFadeSpeed = config.fadeSpeed || 200;
    }

    function hexToRgb(hex) {
        const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
        return result ? `${parseInt(result[1], 16)},${parseInt(result[2], 16)},${parseInt(result[3], 16)}` : "0,0,0";
    }

    function showNotify(msg) {
        const $n = $("#nui-notify");
        $n.stop(true, true).text(msg);

        // If the admin menu is visible, position the notify directly above it
        const $menu = $("#adminMenu");
        if ($menu.is(":visible")) {
            const menuOff = $menu.offset();
            const menuW = $menu.outerWidth();
            // place notify centered above the menu with small gap
            $n.css({ position: 'absolute', left: (menuOff.left + (menuW / 2)) + 'px', top: (menuOff.top - 10) + 'px', transform: 'translate(-50%, -100%)' });
        } else {
            $n.css({ position: 'fixed', left: '50%', top: '12px', transform: 'translateX(-50%)' });
        }

        $n.slideDown(200).delay(2000).slideUp(200);
    }

    function update() {
        $('.nav-item').removeClass('active');
        $(`.nav-item[data-tab="${tabs[currentTab]}"]`).addClass('active');
        $('.tab-content').removeClass('active');
        $(`#${tabs[currentTab]}`).addClass('active');

        // God-Rank Visibility
        if (uiIsGod) {
            $("#superAdminBtn, #rankBtn, #vanishingBtn").show();
        } else {
            $("#superAdminBtn, #rankBtn, #vanishingBtn").hide();
        }

        // BTN Selection & Highlighting
        function getAdminVisibleContainer() {
            if ($('#adminMain').is(':visible')) return $('#adminMain');
            const subs = ['#adminModeSub','#teleportSub','#spawnSub','#vehicleSub','#telePresetsSub','#coordTypeSub','#itemBrowserSub'];
            for (let i = 0; i < subs.length; i++) {
                const s = subs[i];
                if ($(s).is(':visible')) return $(s);
            }
            return $('#adminMain');
        }

        const currentTabId = tabs[currentTab];

        // if tab changed and we switched to the player tab, reset to the main player list
        if (lastTab !== null && lastTab !== currentTab && currentTabId === 'player') {
            selectedPlayerId = null;
            selectedPlayerName = "";
            $("#playerListWrapper").show();
            $("#playerActions").hide();
            currentBtn = 0;
        }

        let btns;
        if (currentTabId === 'admin') {
            const container = getAdminVisibleContainer();
            btns = container.find('button, select, .player-item').filter(':visible');
        } else {
            btns = $(`#${currentTabId}`).find('button, select, .player-item').filter(':visible');
        }

        $('.action-btn, .save-btn, .player-item, select').removeClass('highlight');

        if (btns.length > 0) {
            if (currentBtn >= btns.length) currentBtn = 0;
            if (currentBtn < 0) currentBtn = btns.length - 1;

            const active = $(btns[currentBtn]);
            active.addClass('highlight');

            // Auto-Scroll: find nearest scrollable ancestor (element whose scrollHeight > clientHeight or overflow is auto/scroll)
            let parent = active.parent();
            while (parent.length > 0 && parent[0].id !== 'adminMenu') {
                const el = parent[0];
                const styleOverflow = parent.css('overflow-y');
                if (el.scrollHeight > el.clientHeight || styleOverflow === 'auto' || styleOverflow === 'scroll') break;
                parent = parent.parent();
            }

            if (parent.length > 0) {
                const el = parent[0];
                const parentHeight = el.clientHeight;
                const parentScrollTop = el.scrollTop;
                const activeEl = active[0];
                const activeOffsetTop = activeEl.offsetTop;
                const activeHeight = activeEl.offsetHeight;

                // If the selection is at the very start or end (wrap-around), jump to top/bottom explicitly
                if (btns && btns.length > 0 && (currentBtn === 0 || currentBtn === (btns.length - 1))) {
                    if (currentBtn === 0) {
                        el.scrollTop = 0;
                    } else if (currentBtn === (btns.length - 1)) {
                        el.scrollTop = Math.max(0, el.scrollHeight - parentHeight);
                    }
                } else {
                    if (activeOffsetTop < parentScrollTop + 5) {
                        el.scrollTop = Math.max(0, activeOffsetTop - 10);
                    } else if (activeOffsetTop + activeHeight > parentScrollTop + parentHeight - 5) {
                        el.scrollTop = Math.max(0, activeOffsetTop - parentHeight + activeHeight + 10);
                    }
                }
            }
        }

        if (tabs[currentTab] === 'player' && $("#playerListWrapper").is(":visible")) {
            const now = Date.now();
            if (lastTab !== null && lastTab !== currentTab || (now - lastPlayersFetch) > 3000) {
                lastPlayersFetch = now;
                $.post(`https://${GetParentResourceName()}/getPlayers`, JSON.stringify({}));
            }
        }
        lastTab = currentTab;
    }

    window.addEventListener('message', function(event) {
        if (event.data.type === "ui") {
            if (event.data.settings) applySettings(event.data.settings);
            if (event.data.locales) {
                uiLocales = event.data.locales;
                translateUI();
            }
            if (event.data.isGod !== undefined) uiIsGod = event.data.isGod;

            if (event.data.status) {
                backToAdminMain();
                currentTab = 0;
                currentBtn = 0;

                if (event.data.isGod) $("#superAdminBtn, #tabHistory").show();
                else $("#superAdminBtn, #tabHistory").hide();

                if (event.data.banDurations) {
                    const dList = $("#banDurationList");
                    dList.empty();
                    event.data.banDurations.forEach((d, index) => {
                        dList.append(`<button class="action-btn" onclick="executePlayerAction('selectduration', ${index})">${d.label}</button>`);
                    });
                }
                if (event.data.banReasons) {
                    const rList = $("#banReasonList");
                    rList.empty();
                    event.data.banReasons.forEach((r, index) => {
                        rList.append(`<button class="action-btn" onclick="executePlayerAction('selectreason', ${index})">${r}</button>`);
                    });
                }

                $("#adminMenu").fadeIn(window.uiFadeSpeed || 200);
                update();
            } else {
                $("#adminMenu").fadeOut(window.uiFadeSpeed || 200);
                $("#confirm-modal").hide();
            }

            if (event.data.weathers) {
                availableWeathers = event.data.weathers;
                const wList = $("#weatherList");
                wList.empty();
                availableWeathers.forEach(w => {
                    wList.append(`<button class="action-btn" onclick="executeWorldAction('weather', '${w}')">${w}</button>`);
                });
            }
            if (event.data.times) {
                availableTimes = event.data.times;
                const tList = $("#timeList");
                tList.empty();
                availableTimes.forEach(t => {
                    tList.append(`<button class="action-btn" onclick="executeWorldAction('time', '${t}')">${t}</button>`);
                });
            }
            if (event.data.presets) {
                const pList = $("#presetList");
                pList.empty();
                for (let categoryKey in event.data.presets) {
                    const categoryName = uiLocales[categoryKey] || categoryKey;
                    pList.append(`<div style="color: var(--primary); font-size: 10px; margin-top: 5px; text-transform: uppercase;">${categoryName}</div>`);
                    event.data.presets[categoryKey].forEach((p, index) => {
                        pList.append(`<button class="action-btn" onclick="executeAdminAction('telepreset', {cat: '${categoryKey}', id: ${index}})">${p.name}</button>`);
                    });
                }
            }
        }
        if (event.data.type === "players") {
            allPlayers = event.data.players || [];
                allPlayers.forEach(p => {
                    p.displayName = p.name;
                    if (p.warns > 0) p.displayName += ` <span style="color: var(--danger); font-size: 10px;">(${p.warns} Warns)</span>`;
                });
                filterPlayers();
        }
        if (event.data.type === "announcement") {
            const duration = event.data.duration || 5000;
            $("#announcement-overlay span").text(event.data.title || "ANKÜNDIGUNG");
            $("#announcement-text").text(event.data.text);
            $("#announcement-overlay").fadeIn(500).delay(duration).fadeOut(500);
        }
        if (event.data.type === "main") $('#displayTime').text(event.data.time);
        if (event.data.type === "notify") showNotify(event.data.msg);
        if (event.data.type === "confirmBan") {
            pendingAction = event.data;
            const duration = event.data.duration == 0 ? "permanent" : event.data.duration;
            let text = uiLocales['modal_ban_text'] || "Möchtest du %s wirklich fuer %s Tage bannen?";
            text = text.replace('%s', event.data.targetName).replace('%s', duration);
            $("#confirm-text").text(text);
            $("#confirm-modal").fadeIn(200);
        }
        if (event.data.type === "playerInfo") {
            $("#playerInfoBox").show();
            $("#infoRank").text("Rang: " + (event.data.rank || "User").toUpperCase());
            $("#infoCID").text("CID: " + event.data.citizenid);
            $("#infoLastSeen").text("Zuletzt online: " + event.data.last_seen);
        }
        if (event.data.type === "bans") {
            allBans = event.data.bans || [];
            const bList = $("#banList");
            bList.empty();
            allBans.forEach(b => {
                bList.append(`
                    <div style="background: #111; padding: 8px; margin-bottom: 5px; border-left: 3px solid var(--danger);">
                        <div style="font-weight: bold; color: var(--danger);">${b.name}</div>
                        <div style="font-size: 10px; color: #aaa;">${b.reason}</div>
                        <div style="font-size: 9px; color: #666;">Bis: ${b.expire_text}</div>
                        <button class="action-btn" onclick="executeServerAction('unban', '${b.license}')" style="padding: 4px; font-size: 10px; margin-top: 5px; width: auto;">Entbannen</button>
                    </div>
                `);
            });
        }
        if (event.data.type === "history") {
            allHistory = event.data.history || [];
            filterHistory();
        }
        if (event.data.type === "items") {
            allItems = event.data.items || [];
            filterItems();
        }
        if (event.data.action === "openInput") {
            window.openInput(event.data.data);
        }
        if (event.data.type === "notes") {
            const nList = $("#notesList");
            nList.empty();
            if (event.data.notes && event.data.notes.length > 0) {
                event.data.notes.forEach(n => {
                    nList.append(`
                        <div style="background: #111; padding: 5px; margin-bottom: 3px; border-left: 2px solid var(--primary);">
                            <div style="color: var(--primary); font-weight: bold;">${n.author} (${n.date})</div>
                            <div>${n.note}</div>
                        </div>
                    `);
                });
            } else {
                nList.append('<p style="text-align: center; color: #666;">Keine Notizen vorhanden</p>');
            }
        }
        if (event.data.type === "openSub") {
            const sub = event.data.sub;
            $("#playerActionsMain, #playerNotesSub, #playerRankSub, #playerBanReasonSub, #playerBanDurationSub").hide();
            $(`#${sub}`).show();
            currentBtn = 0;
            update();
        }
        if (event.data.type === "copyCoords") {
            const el = document.createElement('textarea');
            el.value = event.data.coords;
            document.body.appendChild(el);
            el.select();
            document.execCommand('copy');
            document.body.removeChild(el);
        }
    });

    $(document).on('keydown', function(e) {
        if (!$("#adminMenu").is(":visible")) return;
        if ($("#confirm-modal").is(":visible")) return;
        function getCurrentVisibleButtons() {
            const currentTabId = tabs[currentTab];
            if (currentTabId === 'admin') {
                if ($('#adminMain').is(':visible')) return $('#adminMain').find('button, select, .player-item').filter(':visible');
                const subs = ['#adminModeSub','#teleportSub','#spawnSub','#vehicleSub','#telePresetsSub','#coordTypeSub','#itemBrowserSub'];
                for (let i = 0; i < subs.length; i++) {
                    const s = subs[i];
                    if ($(s).is(':visible')) return $(s).find('button, select, .player-item').filter(':visible');
                }
                return $('#adminMain').find('button, select, .player-item').filter(':visible');
            }
            return $(`#${currentTabId}`).find('button, select, .player-item').filter(':visible');
        }

        const btns = getCurrentVisibleButtons();

        if (e.key === "ArrowRight") {
            currentTab = (currentTab + 1) % tabs.length;
            currentBtn = 0;
            update();
        }
        else if (e.key === "ArrowLeft") {
            currentTab = (currentTab - 1 + tabs.length) % tabs.length;
            currentBtn = 0;
            update();
        }
        else if (e.key === "ArrowDown") {
            if (btns.length > 0) {
                currentBtn = (currentBtn + 1) % btns.length;
                update();
            }
        }
        else if (e.key === "ArrowUp") {
            if (btns.length > 0) {
                currentBtn = (currentBtn - 1 + btns.length) % btns.length;
                update();
            }
        }
        else if (e.key === "Enter") {
            const activeEl = document.activeElement;
            if (activeEl && (activeEl.tagName === 'INPUT' || activeEl.tagName === 'TEXTAREA' || activeEl.isContentEditable)) {
                return;
            }

            if (btns.length > 0) {
                e.preventDefault();
                $(btns[currentBtn]).click();
            }
        }
        else if (e.key === "Backspace") {
            // Back navigation: if inside a subpage, go one step back
            const adminSubs = ['#adminModeSub','#telePresetsSub','#coordTypeSub','#itemBrowserSub','#teleportSub','#spawnSub','#vehicleSub'];
            for (let i = 0; i < adminSubs.length; i++) {
                if ($(adminSubs[i]).is(':visible')) {
                    backToAdminMain();
                    e.preventDefault();
                    return;
                }
            }

            if ($('#playerActions').is(':visible')) {
                const playerSubs = ['#playerBanDurationSub','#playerBanReasonSub','#playerRankSub','#playerNotesSub'];
                for (let i = 0; i < playerSubs.length; i++) {
                    if ($(playerSubs[i]).is(':visible')) {
                        backToPlayerActionsMain();
                        e.preventDefault();
                        return;
                    }
                }
                if ($('#playerActionsMain').is(':visible')) {
                    backToPlayerList();
                    e.preventDefault();
                    return;
                }
            }

            const worldSubs = ['#weatherSub','#timeSub','#wavesSub','#densitySub'];
            for (let i = 0; i < worldSubs.length; i++) {
                if ($(worldSubs[i]).is(':visible')) {
                    backToWorldMain();
                    e.preventDefault();
                    return;
                }
            }

            if ($('#banListSub').is(':visible')) {
                backToServerMain();
                e.preventDefault();
                return;
            }
        }
        else if (e.key === "Escape") {
            $.post(`https://${GetParentResourceName()}/close`, JSON.stringify({}));
        }
    });

    window.adminAction = action => $.post(`https://${GetParentResourceName()}/adminAction`, JSON.stringify({ action }));

    window.openAdminSubmenu = type => {
        $("#adminMain").hide();
        // hide any admin subpages first
        $("#telePresetsSub, #coordTypeSub, #itemBrowserSub, #adminModeSub, #teleportSub, #spawnSub, #vehicleSub").hide();

        if (type === 'telepresets') $("#telePresetsSub").show();
        else if (type === 'coordtype') $("#coordTypeSub").show();
        else if (type === 'itembrowser') {
            $("#itemBrowserSub").show();
            filterItems();
        }
        else if (type === 'adminmode') $("#adminModeSub").show();
        else if (type === 'teleport') $("#teleportSub").show();
        else if (type === 'spawn') $("#spawnSub").show();
        else if (type === 'vehicle') $("#vehicleSub").show();

        currentBtn = 0;
        update();
    };

    window.backToAdminMain = () => {
        $("#adminMain").show();
        $("#telePresetsSub, #coordTypeSub, #itemBrowserSub, #adminModeSub, #teleportSub, #spawnSub, #vehicleSub").hide();
        currentBtn = 0;
        update();
    };

    window.openServerSubmenu = type => {
        $("#serverMain").hide();
        if (type === 'banlist') {
            $("#banListSub").show();
            $.post(`https://${GetParentResourceName()}/getBans`, JSON.stringify({}));
        }
        currentBtn = 0;
        update();
    };

    window.backToServerMain = () => {
        $("#serverMain").show();
        $("#banListSub").hide();
        currentBtn = 0;
        update();
    };

    window.filterItems = () => {
        const iList = $("#itemList");
        iList.empty();
        const sorted = allItems.sort((a, b) => a.label.localeCompare(b.label));

        if (sorted.length > 0) {
            sorted.forEach(i => {
                iList.append(`<button class="action-btn" onclick="executeAdminAction('giveitem', '${i.name}')">${i.label} (${i.name})</button>`);
            });
        } else {
            iList.append('<p style="text-align: center; color: #666; font-size: 11px;">Keine Items verfügbar</p>');
        }

        const btns = $("#itemList").find('.action-btn');
        if (btns.length > 0 && currentBtn >= btns.length) currentBtn = 0;
    };

    window.filterHistory = () => {
        const query = $("#historySearch").val().toLowerCase();
        const hList = $("#historyList");
        hList.empty();
        const filtered = allHistory.filter(h => h.citizenid.toLowerCase().includes(query) || h.name.toLowerCase().includes(query));
        filtered.forEach(h => {
            hList.append(`
                <div style="background: #111; padding: 8px; margin-bottom: 5px; border-left: 3px solid var(--primary); font-size: 10px;">
                    <div style="font-weight: bold; color: var(--primary);">${h.name} [${h.rank.toUpperCase()}]</div>
                    <div>CID: ${h.citizenid}</div>
                    <div style="color: #aaa;">Letzter Login: ${h.last_seen}</div>
                </div>
            `);
        });
    };

    window.executeServerAction = (action, val) => {
        $.post(`https://${GetParentResourceName()}/serverAction`, JSON.stringify({ action, data: val }));
    };

    window.executeAdminAction = (action, data) => {
        $.post(`https://${GetParentResourceName()}/adminAction`, JSON.stringify({ action, data }));
    };

    window.openPlayerSubmenu = (id, name) => {
        selectedPlayerId = id;
        selectedPlayerName = name;
        $("#selectedPlayerName").text(name);
        $("#playerInfoBox").hide();
        $("#playerListWrapper").hide();
        $("#playerActions").show();
        backToPlayerActionsMain();
        
        $.post(`https://${GetParentResourceName()}/getPlayerInfo`, JSON.stringify({ id: id }));
        
        currentBtn = 0;
        update();
    };

    window.openPlayerSubmenu_Notes = () => {
        $("#playerActionsMain, #playerRankSub").hide();
        $("#playerNotesSub").show();
        $.post(`https://${GetParentResourceName()}/getNotes`, JSON.stringify({ id: selectedPlayerId }));
        currentBtn = 0;
        update();
    };

    window.openPlayerSubmenu_Rank = () => {
        $("#playerActionsMain, #playerNotesSub").hide();
        $("#playerRankSub").show();
        currentBtn = 0;
        update();
    };

    window.backToPlayerActionsMain = () => {
        $("#playerActionsMain").show();
        $("#playerNotesSub, #playerRankSub, #playerBanReasonSub, #playerBanDurationSub").hide();
        currentBtn = 0;
        update();
    };

    window.confirmAction = success => {
        $("#confirm-modal").fadeOut(200);
        if (success && pendingAction) {
            $.post(`https://${GetParentResourceName()}/confirmBan`, JSON.stringify(pendingAction));
        }
        pendingAction = null;
    };

    window.update = update;
    window.backToPlayerList = () => {
        selectedPlayerId = null;
        selectedPlayerName = "";
        $("#playerListWrapper").show();
        $("#playerActions").hide();
        currentBtn = 0;
        update();
    };

    window.executePlayerAction = (action, val) => {
        if (!selectedPlayerId) return;
        $.post(`https://${GetParentResourceName()}/playerAction`, JSON.stringify({ action, id: selectedPlayerId, name: selectedPlayerName, data: val }));
    };

    window.openWorldSubmenu = type => {
        $("#worldMain").hide();
        if (type === 'weather') $("#weatherSub").show();
        else if (type === 'time') $("#timeSub").show();
        else if (type === 'waves') $("#wavesSub").show();
        else if (type === 'density') $("#densitySub").show();
        currentBtn = 0;
        update();
    };

    window.backToWorldMain = () => {
        $("#worldMain").show();
        $("#weatherSub, #timeSub, #wavesSub, #densitySub").hide();
        currentBtn = 0;
        update();
    };

    window.filterPlayers = () => {
        // no search input yet: always show full player list
        const query = "";
        const pList = $("#playerList");
        pList.empty();

        const filtered = allPlayers.slice();

            if (filtered.length > 0) {
            filtered.forEach(p => {
                const safeName = JSON.stringify(p.name);
                pList.append(`
                    <div class="player-item action-btn" onclick='openPlayerSubmenu(${p.id}, ${safeName})'>
                        [${p.id}] ${p.displayName || p.name}
                    </div>
                `);
            });
            if (tabs[currentTab] === 'player') {
                const btns = $(`#${tabs[currentTab]}`).find('button, select, .player-item').filter(':visible');
                const firstPlayer = $(`#playerList .player-item`).first();
                if (firstPlayer.length > 0) {
                    const idx = btns.index(firstPlayer);
                    if (idx >= 0) currentBtn = idx;
                }
            }
        } else {
            const noPlayers = uiLocales['no_players'] || 'Keine Spieler gefunden';
            pList.append(`<p style="text-align: center; font-size: 12px; color: #666;">${noPlayers}</p>`);
        }

        const btns = $(`#${tabs[currentTab]}`).find('.action-btn, .save-btn, select, .player-item').filter(':visible');
        btns.removeClass('highlight');
        if (btns.length > 0) $(btns[currentBtn]).addClass('highlight');
    };

    window.executeWorldAction = (type, val) => {
        if (type === 'weather') {
            $.post(`https://${GetParentResourceName()}/setWeatherAndTime`, JSON.stringify({ weather: val }));
        } else if (type === 'time') {
            $.post(`https://${GetParentResourceName()}/setWeatherAndTime`, JSON.stringify({ time: val }));
        } else if (type === 'waves') {
            $.post(`https://${GetParentResourceName()}/setWeatherAndTime`, JSON.stringify({ waves: val }));
        } else if (type === 'density') {
            $.post(`https://${GetParentResourceName()}/setWeatherAndTime`, JSON.stringify({ density: val }));
        }
    };

    $('#applyWorld').on('click', () => $.post(`https://${GetParentResourceName()}/setWeatherAndTime`, JSON.stringify({ weather: $("#admWeather").val(), time: $("#admTime").val() })));

    // ========================
    // Custom Input Dialog
    // ========================
    let inputCallback = null;

    window.openInput = function(data) {
        const dialog = $('#input-dialog');
        const field = $('#input-field');
        const title = $('#input-title');
        
        $.post(`https://${GetParentResourceName()}/setInputState`, JSON.stringify({ active: true }));

        title.text(data.title || 'Eingabe');
        field.val(data.defaultText || '');
        field.attr('maxlength', data.maxLength || 200);
        field.attr('placeholder', data.placeholder || '');
        
        inputCallback = data.callback || null;
        
        dialog.fadeIn(150);
        field.focus();
    };

    window.submitInput = function() {
        const value = $('#input-field').val();
        $('#input-dialog').fadeOut(150);
        
        if (inputCallback) {
            $.post(`https://${GetParentResourceName()}/${inputCallback}`, JSON.stringify({ input: value }));
        }
        
        $.post(`https://${GetParentResourceName()}/setInputState`, JSON.stringify({ active: false }));

        inputCallback = null;
    };

    window.cancelInput = function() {
        $('#input-dialog').fadeOut(150);
        $.post(`https://${GetParentResourceName()}/setInputState`, JSON.stringify({ active: false }));
        inputCallback = null;
    };

    // Handle Enter key in input field
    $('#input-field').on('keypress', function(e) {
        if (e.which === 13) { // Enter key
            submitInput();
        }
    });

    // Handle Escape to close input
    $(document).on('keyup', function(e) {
        if (e.key === 'Escape' && $('#input-dialog').is(':visible')) {
            cancelInput();
        }
    });
});
