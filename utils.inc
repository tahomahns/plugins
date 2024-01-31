#if defined _ih_utils_included
	#endinput
#endif
#define _ih_utils_included

#include <amxmodx>

stock bool:is_user_player(id)
{
	if (is_user_bot(id))
		return false;
	
	if (is_user_hltv(id))
		return false;

	return true;
}

stock bool:is_user_valid(id)
{
    if (!is_user_connected(id))
		return false;
	
    if (!is_user_player(id))
		return false;
    
    return true;
}

stock bool:is_user_admin_flags(id, const flags[])
{
    if (!is_user_valid(id))
        return false;

    if (!strcmp(flags, "g") && get_user_flags(id) & ADMIN_IMMUNITY)
        return true;

    if (!strcmp(flags, "a") && get_user_flags(id) & ADMIN_BAN)
        return true;

    if (!strcmp(flags, "m") && get_user_flags(id) & ADMIN_KICK)
        return true;

    return false;
}

stock get_num_moderators()
{
	new moderators;
	new const maxplayers = get_maxplayers();

	for (new i = 1; i <= maxplayers; i++)
	{
		if (is_user_admin_flags(i, "m") && 
			!is_user_admin_flags(i, "a") && 
			!is_user_admin_flags(i, "g"))
		{
			moderators++;
		}
	}

	return moderators;
}

stock get_num_admins()
{
	new admins;
	new const maxplayers = get_maxplayers();

	for (new i = 1; i <= maxplayers; i++)
	{
		if (is_user_admin_flags(i, "a") && 
			is_user_admin_flags(i, "g"))
		{
			admins++;
		}
	}

	return admins;
}

stock bool:is_moderator_online()
{
	return get_num_moderators() > 0;
}

stock bool:is_admin_online()
{
	return get_num_admins() > 0;
}

stock print_to_admins(message[], any: ...)
{
	static buffer[128];
	vformat(buffer, charsmax(buffer), message, 2);

	new players[MAX_PLAYERS], pnum;
	get_players(players, pnum, "ch");

	for (new i = 0; i < pnum; i++)
	{
		new const target = players[i];

		if (is_user_admin_flags(target, "m"))
			client_print_color(target, print_team_blue, buffer);
    }
}

stock super_cmd(id, cmd[], any: ...)
{
	static buffer[128];
  	vformat(buffer, charsmax(buffer), cmd, 3);
	message_begin(MSG_ONE, SVC_DIRECTOR, _, id);
	write_byte(strlen(buffer) + 2);
	write_byte(10);
	write_string(buffer);
	message_end();
}

stock fnRegisterSayCmd(const sz_cmd[], const sz_short[], const sz_func[], flags = -1, sz_info[] = "")
{
	new sz_temp[65], sz_infolang[65];
	format(sz_infolang, charsmax(sz_infolang), "%L", LANG_SERVER, sz_info);
	format(sz_temp, charsmax(sz_temp), "say /%s", sz_cmd);
	register_clcmd(sz_temp, sz_func, flags, sz_infolang);
	format(sz_temp, charsmax(sz_temp), "%s", sz_cmd);
	register_clcmd(sz_temp, sz_func, flags, sz_infolang);
	format(sz_temp, charsmax(sz_temp), "/%s", sz_cmd);
	register_clcmd(sz_temp, sz_func, flags, sz_infolang);
	format(sz_temp, charsmax(sz_temp), "say /%s", sz_short);
	register_clcmd(sz_temp, sz_func, flags, sz_infolang);
	format(sz_temp, charsmax(sz_temp), "%s", sz_short);
	register_clcmd(sz_temp, sz_func, flags, sz_infolang);
	format(sz_temp, charsmax(sz_temp), "/%s", sz_short);
	register_clcmd(sz_temp, sz_func, flags, sz_infolang);
}
