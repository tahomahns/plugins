// Watcher Manager
// Отдельное спасибо Garey за идею и реализацию
// killabez1337 спасибо за переделку под mysql

// SQL_HOST - Имя хоста
// SQL_USER - Пользователь
// SQL_PASS - Пароль
// SQL_DATABASE - Таблица

#include <amxmodx>
#include <amxmisc>
#include <sqlx>
#include <utils>

new const WATCHER_PRIVILEGES    = ADMIN_LEVEL_A;
new const COLUM_WATCHER[]       = "watcher_server";
new const TABLE_WATCHER[]       = "hns_watcher";
new const SQL_HOST[]            = "host";
new const SQL_USER[]            = "user";
new const SQL_PASS[]            = "password";
new const SQL_DATABASE[]        = "database";
new const WATCHER_TOGGLE_INI[]	= "watcher_toggle.ini";

const MIN_PLAYERS_FOR_VOTE      = 4;

enum _:WATCHER_DATA_S
{
    watcher_steamid[MAX_AUTHID_LENGTH],
    watcher_id
};

enum _:PLAYER_DATA_S
{
    bool:blacklist_marked,
    bool:rockedthevote,
    votes_to_watcher
};

enum _:VOTE_DATA_S
{
    rocked_players,
    bool:in_progress
};

enum _:SQL
{
    SQL_TABLE,
    SQL_SELECT,
    SQL_INSERT,
    SQL_LOADWATCHER,
    SQL_SAVEWATCHER,
    SQL_ADDBLACKLIST,
    SQL_LOADBLACKLIST,
    SQL_MENUBLACKLIST,
    SQL_REMOVEBLACKLIST
};

new g_sWatcherData[WATCHER_DATA_S];
new g_sPlayerData[MAX_PLAYERS + 1][PLAYER_DATA_S];
new g_sVoteData[VOTE_DATA_S];
new g_iMaxPlayers;
new Handle:g_hSqlTuple;
new bool:g_bWatcherToggle;
new g_szWatcherTogglePath[128];
new const g_szPrefix[] = "^4[Watcher Manager]^1";

public plugin_init()
{
	register_plugin("Watcher System", "Release", "killabez1337 & Garey"); // Minor changes by tahoma

	register_clcmd("say rnw", "RockNewWatcher");
	register_clcmd("say /rnw", "RockNewWatcher");
	register_clcmd("say unrnw", "UnRockNewWatcher");
	register_clcmd("say /unrnw", "UnRockNewWatcher");
	register_clcmd("say /watcher", "ChooseWatcher");
	register_clcmd("watchermanager", "ChooseWatcher");

	g_iMaxPlayers = get_maxplayers();

	RegisterSQL();
}

public plugin_cfg()
{
	new buffer_path[128];
	get_datadir(buffer_path, charsmax(buffer_path));
	format(g_szWatcherTogglePath, charsmax(g_szWatcherTogglePath), "%s/%s", buffer_path, WATCHER_TOGGLE_INI);

	LoadWatcherToggle();
	LoadWatcher();
}

public plugin_end()
{
	SaveWatcher();
	SQL_FreeHandle(g_hSqlTuple);
}

public client_putinserver(id)
{
    SQL_Select(id);
}

public client_authorized(id, const authid[])
{
	if (equal(g_sWatcherData[watcher_steamid], authid))
		DesignateWatcher(id);
	
	DesignateBlackList(id, authid);
}

public client_disconnected(id)
{
	UnRockNewWatcher(id);

	if (g_sWatcherData[watcher_id] == id)
	{
		client_print_color(0, print_team_blue, "%s ^3%n ^1(Watcher) вышел! Ждите его, либо выберите нового (в чат^4 rnw^1)", g_szPrefix, g_sWatcherData[watcher_id]);
		g_sWatcherData[watcher_id] = 0;	
	}

	g_sPlayerData[id][votes_to_watcher] = 0;
	g_sPlayerData[id][rockedthevote] = false;
	g_sPlayerData[id][blacklist_marked] = false;
}

public client_infochanged(id)
{
	if (IsWatcher(id))
		DesignateWatcher(id);
}

public bool:IsWatcher(id)
{
	if (id && g_sWatcherData[watcher_id] == id)
		return true;

	return false;
}

public LoadWatcherToggle()
{
	new fp = fopen(g_szWatcherTogglePath, "r");

	if (fp)
	{
		new buffer[32];
		fgets(fp, buffer, charsmax(buffer));

		if (strlen(buffer))
			g_bWatcherToggle = str_to_num(buffer) != 0;

		fclose(fp);
	}
}

public SaveWatcherToggle()
{
	delete_file(g_szWatcherTogglePath);

	new fp = fopen(g_szWatcherTogglePath, "w");

	if (fp)
	{
		new buffer[32];
		format(buffer, charsmax(buffer), "%i", g_bWatcherToggle);
		fputs(fp, buffer);
		fclose(fp);
	}
}

public RegisterSQL()
{
    g_hSqlTuple = SQL_MakeDbTuple(SQL_HOST, SQL_USER, SQL_PASS, SQL_DATABASE);   
    SQL_SetCharset(g_hSqlTuple, "utf-8");

    new query[512];
    new data[1];
    data[0] = SQL_TABLE;

    format(query, charsmax(query), "\
        CREATE TABLE IF NOT EXISTS `%s` \
        ( \
            `player_steamid`    VARCHAR(24) NULL DEFAULT NULL, \
            `watcher_server`  	INT(11) NOT NULL DEFAULT 0, \
            `blacklist_marked`  INT(11) NOT NULL DEFAULT 0 \
        );", TABLE_WATCHER);
    
    SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", query, data, sizeof(data));
}

public QueryHandler(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime)
{
    if (failstate != TQUERY_SUCCESS)
    {
        log_amx("SQL Error #%d - %s", errnum, error);
        return;
    }

    switch (data[0])
    {
        case SQL_SELECT:
        {
            new const id = data[1];

            if (!SQL_NumResults(query))
                SQL_Insert(id);
        }
        case SQL_LOADWATCHER:
        {
            if (SQL_NumResults(query))
            {
                new const index_steamid = SQL_FieldNameToNum(query, "player_steamid");
                SQL_ReadResult(query, index_steamid, g_sWatcherData[watcher_steamid], charsmax(g_sWatcherData[watcher_steamid]));
            }
        }
        case SQL_LOADBLACKLIST:
        {
            if (SQL_NumResults(query))
            {
                new const index_blacklist = SQL_FieldNameToNum(query, "blacklist_marked");
                
                if (SQL_ReadResult(query, index_blacklist))
                {
                    new const id = data[1];

                    g_sPlayerData[id][votes_to_watcher] = 0;
                    g_sPlayerData[id][blacklist_marked] = true;

                    if (IsWatcher(id))
                        RemoveWatcher();
                }
            }
        }
        case SQL_MENUBLACKLIST:
        {
            new const num_results = SQL_NumResults(query);

            if (num_results)
            {
                new menu = menu_create("\rRemove from blacklist", "RemoveBlackListMenuHandler");

                new const index_steamid = SQL_FieldNameToNum(query, "player_steamid");
                new const id = data[1];

                for (new i = 0; i < num_results; i++)
                {
					new authid[MAX_AUTHID_LENGTH];
					SQL_ReadResult(query, index_steamid, authid, charsmax(authid));

					new const target = find_player("c", authid)

					if (target)
						menu_additem(menu, fmt("%n \d(%s)", target, authid), authid);
					else
						menu_additem(menu, fmt("\d%s", authid), authid);

					if (i < num_results - 1)
                        SQL_NextRow(query);
                }

                menu_display(id, menu);
            }
        }
    }
}

public SQL_Select(id)
{
    new query[512];
    new data[2];
    data[0] = SQL_SELECT;
    data[1] = id;

    new authid[MAX_AUTHID_LENGTH];
    get_user_authid(id, authid, charsmax(authid));

    formatex(query, charsmax(query), "\
        SELECT * \
		FROM `%s` \
		WHERE `player_steamid` = '%s'", TABLE_WATCHER, authid);

    SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", query, data, sizeof(data));
}

public SQL_Insert(id)
{
    new query[512];
    new data[1];
    data[0] = SQL_INSERT;

    new authid[MAX_AUTHID_LENGTH];
    get_user_authid(id, authid, charsmax(authid));

    formatex(query, charsmax(query), "\
        INSERT INTO `%s` \
        ( \
            player_steamid \
        ) \
        VALUES \
        ( \
            '%s' \
        )", TABLE_WATCHER, authid);

    SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", query, data, sizeof(data));
}

public RockNewWatcher(id)
{
	if (!g_bWatcherToggle)
		return;

	if (is_admin_online() || is_moderator_online())
	{
		client_print_color(id, print_team_blue, "%s Команда^4 rnw^1 недоступна, т.к на сервере^4 админ^1!", g_szPrefix);
		return;
	}

	new const playersnum = get_playersnum();

	if (playersnum < MIN_PLAYERS_FOR_VOTE)
	{
		client_print_color(id, print_team_blue, "%s Не хватает игроков для голосования за Watcher... (нужно > %i)", g_szPrefix, MIN_PLAYERS_FOR_VOTE - 1);
		return;
	}

	new need_to_start_vote;

	if (g_sPlayerData[id][rockedthevote])
	{
		need_to_start_vote = floatround(0.66 * playersnum - g_sVoteData[rocked_players]);
		client_print_color(id, print_team_blue, "%s нужно + %i для голосования", g_szPrefix, need_to_start_vote);
	}
	else
	{
		g_sPlayerData[id][rockedthevote] = true;
		g_sVoteData[rocked_players]++;

		need_to_start_vote = floatround(0.66 * playersnum - g_sVoteData[rocked_players]);

		if (need_to_start_vote > 0)
			client_print_color(0, print_team_blue, "%s ^3%n ^1хочу изменить Watcher нужно + %i для старта голосования!", g_szPrefix, id, need_to_start_vote);
		else
		{
			client_print_color(0, print_team_blue, "%s Начало голосования за нового Watcher!", g_szPrefix);
			StartVote();
		}
	}
}

public UnRockNewWatcher(id)
{
	if (g_sPlayerData[id][rockedthevote])
	{
		if (is_user_connected(id))
			client_print_color(id, print_team_blue, "%s Вы отменили свой голос за новое голосование Watcher!", g_szPrefix);

		g_sPlayerData[id][rockedthevote] = false;

		if (g_sVoteData[rocked_players] > 0)
			g_sVoteData[rocked_players]--;
	}
}

public StartVote()
{
    if (g_sVoteData[in_progress])
        return;

    for (new i = 0; i <= g_iMaxPlayers; i++)
        g_sPlayerData[i][rockedthevote] = false;

    g_sVoteData[in_progress] = true;
    g_sVoteData[rocked_players] = 0;

    for (new i = 1; i <= g_iMaxPlayers; i++)
    {
        if (is_user_valid(i))
            VoteWatcher(i);
    }

    set_task(15.0, "CheckVotes");
}

public VoteWatcher(id)
{
	new menu = menu_create("\rVote for New Watcher", "VoteWatcherHandler");

	for (new i = 1; i <= g_iMaxPlayers; i++)
	{
		if (!is_user_valid(i))
			continue;

		if (is_user_admin_flags(i, "m"))
			continue;

		if (g_sPlayerData[i][blacklist_marked])
			continue;

		menu_additem(menu, fmt("%n", i), fmt("%i", get_user_userid(i)));
	}

	menu_display(id, menu);
}

public VoteWatcherHandler(id, menu, item)
{
	if (item == MENU_EXIT || !g_sVoteData[in_progress])
	{
		menu_destroy(menu);
		return PLUGIN_HANDLED;
	}

	new info[32];
	menu_item_getinfo(menu, item, _, info, charsmax(info));
	new const target = find_player("k", str_to_num(info));

	if (target)
	{
		g_sPlayerData[target][votes_to_watcher]++;
		client_print_color(0, print_team_blue, "%s ^3%n ^1проголосовал за ^3%n ^1(%i)", g_szPrefix, id, target, g_sPlayerData[target][votes_to_watcher]);
	}
	else
	{
		client_print_color(id, print_team_blue, "%s Вы не можете проголосовать, игрок отключен!", g_szPrefix);
		VoteWatcher(id);
	}

	menu_destroy(menu);
	return PLUGIN_HANDLED;
}

public CheckVotes()
{
    new players[MAX_PLAYERS], pnum;
    get_players(players, pnum, "ch");

    new maxvotes = g_sPlayerData[players[0]][votes_to_watcher];
    new newwatcher = players[0];

    for (new i = 0; i < pnum; i++)
    {
        new const target = players[i];

        if (maxvotes < g_sPlayerData[target][votes_to_watcher])
        {
            newwatcher = target;
            maxvotes = g_sPlayerData[target][votes_to_watcher];
        }
    }

    if (!maxvotes)
    {
        client_print_color(0, print_team_blue, "%s Недостаточно голосов для нового Watcher", g_szPrefix);
        return;
    }

    new candidates[MAX_PLAYERS], cnum;

    for (new i = 0; i < pnum; i++)
	{
		new const target = players[i];

		if (maxvotes == g_sPlayerData[target][votes_to_watcher])
		{			
			candidates[cnum] = target;
			cnum++;
		}
	}

    if (cnum > 1)
    {
        newwatcher = candidates[random_num(0, cnum - 1)];
        client_print_color(0, print_team_blue, "%s Новый Watcher ^3%n ^1выбран рандомно %i игрок.", g_szPrefix, newwatcher, cnum);
    }
	else
		client_print_color(0, print_team_blue, "%s Новым Watcher выбран ^3%n ^1с %i голосов!", g_szPrefix, newwatcher, maxvotes);

    DesignateWatcher(newwatcher);

    g_sVoteData[in_progress] = false;

    for (new i = 0; i <= g_iMaxPlayers; i++)
        g_sPlayerData[i][votes_to_watcher] = 0;
}

public DesignateWatcher(id)
{
	if (g_sWatcherData[watcher_id])
		RemoveWatcher();

	if (g_sPlayerData[id][blacklist_marked])
		return;

	g_sWatcherData[watcher_id] = id;
	get_user_authid(g_sWatcherData[watcher_id], g_sWatcherData[watcher_steamid], charsmax(g_sWatcherData[watcher_steamid]));	
	SaveWatcher();

	if (!g_bWatcherToggle)
		return;

	if (!is_user_admin_flags(g_sWatcherData[watcher_id], "m"))
	{
        remove_user_flags(g_sWatcherData[watcher_id], ADMIN_USER);
        set_user_flags(g_sWatcherData[watcher_id], WATCHER_PRIVILEGES);
    }
}

public RemoveWatcher()
{
	if (!is_user_admin_flags(g_sWatcherData[watcher_id], "m"))
	{
		remove_user_flags(g_sWatcherData[watcher_id], WATCHER_PRIVILEGES);
		set_user_flags(g_sWatcherData[watcher_id], ADMIN_USER);
	}

	g_sWatcherData[watcher_id] = 0;
	arrayset(g_sWatcherData[watcher_steamid], 0, sizeof(g_sWatcherData[watcher_steamid]));
	SaveWatcher();
}

public SaveWatcher()
{
    new query[512];
    new data[1];
    data[0] = SQL_SAVEWATCHER;

    if (strlen(g_sWatcherData[watcher_steamid]))
    {
        formatex(query, charsmax(query), "\
            UPDATE  `%s` \
            SET     `%s` = 1 \
            WHERE   `player_steamid` = '%s' \
            ", TABLE_WATCHER, COLUM_WATCHER, g_sWatcherData[watcher_steamid]);
    }
    else
    {
        formatex(query, charsmax(query), "\
            UPDATE  `%s` \
            SET     `%s` = 0 \
            WHERE   `%s` = 1 \
            ", TABLE_WATCHER, COLUM_WATCHER, COLUM_WATCHER);
    }

    SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", query, data, sizeof(data));
}

public LoadWatcher()
{
    new query[512];
    new data[1];
    data[0] = SQL_LOADWATCHER;

    formatex(query, charsmax(query), "\
            SELECT  * \
            FROM    `%s` \
            WHERE   `%s` = 1 \
            ", TABLE_WATCHER, COLUM_WATCHER);

    SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", query, data, sizeof(data));
}

public ChooseWatcher(id)
{
	if (is_user_admin_flags(id, "m"))
		SuperWatcher(id);
	else
	{
		if (g_sWatcherData[watcher_id])
		{
			if (IsWatcher(id))
				WatcherMenu(id);
			else
				client_print_color(id, print_team_blue, "%s Новый Watcher %n", g_szPrefix, g_sWatcherData[watcher_id]);
		}
		else
		{
			if (strlen(g_sWatcherData[watcher_steamid]))
				client_print_color(id, print_team_blue, "%s Watcher выбран автоматически, но не подключен к серверу", g_szPrefix);
			else
				client_print_color(id, print_team_blue, "%s Watcher автоматически не выбран!", g_szPrefix);
		}			
	}

	return PLUGIN_HANDLED;
}

public SuperWatcher(id)
{
	new title[128];

	if (g_sWatcherData[watcher_id])
		format(title, charsmax(title), "\rWatcher Managment^n\dCurrent watcher: %n (%s)", g_sWatcherData[watcher_id], g_sWatcherData[watcher_steamid]);
	else if (strlen(g_sWatcherData[watcher_steamid]))
		format(title, charsmax(title), "\rWatcher Managment^n\dCurrent watcher (offline): %s", g_sWatcherData[watcher_steamid]);
	else
		format(title, charsmax(title), "\rWatcher Managment^n\dWatcher has not been chosen");

	new menu = menu_create(title, "SuperWatcherHandler");

	if ((g_sWatcherData[watcher_id] || strlen(g_sWatcherData[watcher_steamid])) && g_bWatcherToggle)
		menu_additem(menu, "Remove current watcher", "1");
	else
		menu_additem(menu, "\dRemove current watcher", "1");

	if (g_bWatcherToggle)
		menu_additem(menu, "Choose new watcher", "2");
	else
		menu_additem(menu, "\dChoose new watcher", "2");

	menu_addblank(menu, 0);
	menu_additem(menu, "Add to watcher blacklist", "3");
	menu_additem(menu, "Remove from blacklist", "4", ADMIN_BAN);
	menu_addtext2(menu, "\d(Players in blacklist can't been chosen)");
	menu_addblank2(menu);
	menu_additem(menu, fmt("Watcher toggle: %s", g_bWatcherToggle ? "\y[on]" : "\r[off]"), "7", ADMIN_BAN);
	menu_addtext(menu, "\d(Toggles of watcher privileges)", 0);
	menu_display(id, menu);
}

public SuperWatcherHandler(id, menu, item)
{
	if (item == MENU_EXIT)
	{
		menu_destroy(menu);
		return PLUGIN_HANDLED;
	}

	new info[6];
	menu_item_getinfo(menu, item, _, info, charsmax(info));
	new const key = str_to_num(info);

	switch (key)
	{
		case 1:
		{
			if (g_sWatcherData[watcher_id] || strlen(g_sWatcherData[watcher_steamid]))
			{
				if (g_sWatcherData[watcher_id])
					client_print_color(0, print_team_blue, "%s Админ ^3%n ^1забрал ^3%n ^1Watcher привелегию", g_szPrefix, id, g_sWatcherData[watcher_id]);
				else if (strlen(g_sWatcherData[watcher_steamid]))
					client_print_color(0, print_team_blue, "%s Админ ^3%n ^1забрал ^3%s ^1Watcher привелегию", g_szPrefix, id, g_sWatcherData[watcher_steamid]);

				RemoveWatcher();
			}
			else
				SuperWatcher(id);		
		}
		case 2: WatcherMenu(id);
		case 3: AddBlackListMenu(id);
		case 4: RemoveBlackListMenu(id);
		case 7:
		{
			if (g_bWatcherToggle)
			{
				if (g_sWatcherData[watcher_id])
				{
					remove_user_flags(g_sWatcherData[watcher_id], WATCHER_PRIVILEGES);
					set_user_flags(g_sWatcherData[watcher_id], ADMIN_USER);
				}

				g_bWatcherToggle = false;	
				client_print_color(0, print_team_blue, "%s Админ ^3%n ^1отключил^4 Watcher Manager", g_szPrefix, id);
				SaveWatcherToggle();
				SuperWatcher(id);
			}
			else
			{
				if (g_sWatcherData[watcher_id])
				{
					remove_user_flags(g_sWatcherData[watcher_id], ADMIN_USER);
					set_user_flags(g_sWatcherData[watcher_id], WATCHER_PRIVILEGES);
				}

				g_bWatcherToggle = true;
				client_print_color(0, print_team_blue, "%s Админ ^3%n ^1включил^4 Watcher Manager", g_szPrefix, id);
				SaveWatcherToggle();
				SuperWatcher(id);
			}
		}
	}

	menu_destroy(menu);
	return PLUGIN_HANDLED;
}

public WatcherMenu(id)
{
	if (!g_bWatcherToggle)
		return;

	new menu = menu_create("\rChoose New Watcher", "WatcherMenuHandler");

	new players[MAX_PLAYERS], pnum;
	get_players(players, pnum, "ch");

	for (new i = 0; i < pnum; i++)
	{
		new const target = players[i];

		if (target == id)
			continue;

		if (is_user_admin_flags(target, "m"))
			continue;

		if (g_sPlayerData[target][blacklist_marked])
			continue;

		menu_additem(menu, fmt("%n", target), fmt("%i", get_user_userid(target)));
	}

	menu_display(id, menu);
}

public WatcherMenuHandler(id, menu, item)
{
	if (item == MENU_EXIT || ~get_user_flags(id) & ADMIN_LEVEL_A)
	{
		menu_destroy(menu);
		return PLUGIN_HANDLED;
	}

	new info[32];
	menu_item_getinfo(menu, item, _, info, charsmax(info));
	new const userid = str_to_num(info);
	new const target = find_player("k", userid);

	if (target)
		MakeWatcher(id, target);

	menu_destroy(menu);
	return PLUGIN_HANDLED;
}

public MakeWatcher(maker, id)
{
	if (!is_user_connected(id))
	{
		client_print_color(maker, print_team_blue, "%s ID игрока, которого вы выбрали, отключен", g_szPrefix);
		return;
	}

	DesignateWatcher(id);
	client_print_color(0, print_team_blue, "%s ^3%n ^1выбрал ^3%n ^1нового Watcher", g_szPrefix, maker, id);
}

public AddBlackListMenu(id)
{
	new menu = menu_create("\rAdd to watcher blacklist", "AddBlackListMenuHandler");

	new players[MAX_PLAYERS], pnum;
	get_players(players, pnum, "ch");

	for (new i = 0; i < pnum; i++)
	{
		new const target = players[i];

		if (is_user_admin_flags(target, "m"))
			continue;

		if (g_sPlayerData[target][blacklist_marked])
			continue;

		new authid[MAX_AUTHID_LENGTH];
		get_user_authid(target, authid, charsmax(authid));
		menu_additem(menu, fmt("%n", target), authid);
	}

	menu_display(id, menu);
}

public AddBlackListMenuHandler(id, menu, item)
{
	if (item == MENU_EXIT)
	{
		menu_destroy(menu);
		return PLUGIN_HANDLED;
	}

	new authid[MAX_AUTHID_LENGTH];
	menu_item_getinfo(menu, item, _, authid, charsmax(authid));
	new const target = find_player("c", authid);

	if (target)
	{
		if (!g_sPlayerData[target][blacklist_marked])
			print_to_admins("%s Игрок: ^3%n ^1добавлен в чёрный список^4 Watchers^1.", g_szPrefix, target);
	}
	else
		print_to_admins("%s Игрок: ^3%s ^1добавлен в чёрный список^4 Watchers^1.", g_szPrefix, authid);

	AddBlackList(authid);

	if (target && !g_sPlayerData[target][blacklist_marked])
		DesignateBlackList(target, authid);

	menu_destroy(menu);
	return PLUGIN_HANDLED;
}

public AddBlackList(const authid[])
{
    new query[512];
    new data[1];
    data[0] = SQL_ADDBLACKLIST;

    formatex(query, charsmax(query), "\
        UPDATE  `%s` \
        SET     `blacklist_marked` = 1 \
        WHERE   `player_steamid` = '%s' \
        ", TABLE_WATCHER, authid);

    SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", query, data, sizeof(data));
}

public DesignateBlackList(id, const authid[])
{
    new query[512];
    new data[2];
    data[0] = SQL_LOADBLACKLIST;
    data[1] = id;

    formatex(query, charsmax(query), "\
            SELECT  * \
            FROM    `%s` \
            WHERE   `player_steamid` = '%s' \
            ", TABLE_WATCHER, authid);

    SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", query, data, sizeof(data));
}

public RemoveBlackListMenu(id)
{
    new query[512];
    new data[2];
    data[0] = SQL_MENUBLACKLIST;
    data[1] = id;

    formatex(query, charsmax(query), "\
            SELECT  * \
            FROM    `%s` \
            WHERE   `blacklist_marked` = 1 \
            ", TABLE_WATCHER);
	
    SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", query, data, sizeof(data));
}

public RemoveBlackListMenuHandler(id, menu, item)
{
	if (item == MENU_EXIT)
	{
		menu_destroy(menu);
		return PLUGIN_HANDLED;
	}

	new authid[MAX_AUTHID_LENGTH];
	menu_item_getinfo(menu, item, _, authid, charsmax(authid));

	print_to_admins("%s Steam ID Игрока: ^3%s ^1Удален из черного списка^4 Watchers^1.", g_szPrefix, authid);
	RemoveBlackList(authid);

	menu_destroy(menu);
	return PLUGIN_HANDLED;
}

public RemoveBlackList(const authid[])
{
    new query[512];
    new data[1];
    data[0] = SQL_REMOVEBLACKLIST;
 
    formatex(query, charsmax(query), "\
        UPDATE  `%s` \
        SET     `blacklist_marked` = 0 \
        WHERE   `player_steamid` = '%s' \
        ", TABLE_WATCHER, authid);

    new const id = find_player("c", authid);
    g_sPlayerData[id][blacklist_marked] = false;

    SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", query, data, sizeof(data));
}