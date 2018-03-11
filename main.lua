--------------------------------------------------------------------------------
-- Background Checks on Users
--------------------------------------------------------------------------------
-- socket and JSON stuff
require("socket");
local http=require("socket.http");
local JSON = require("JSON");

--------------------------------------------------------------------------------
-- Retrieve API key from file
--------------------------------------------------------------------------------
function get_apikey(file)
	-- read api
	local f = io.open(file or "./APIKEY");
	assert(f,("no such api key file '%s'"):format(file))
	local APIKEY=f:read("*a"); f:close();
	assert(APIKEY,"no apikey");
	return APIKEY;
end

--------------------------------------------------------------------------------
-- Get list of names from file.
--------------------------------------------------------------------------------
function get_names(file)
	local file = ((file and io.open(file)) or io.stdin);
	assert(file,("no such name source"));
	local names={};

	-- Gather names
	for line in file:lines() do
		names[#names+1] = line;
	end

	file:close();
	return names;
end

--------------------------------------------------------------------------------
-- Mode lookup table
--------------------------------------------------------------------------------
Modes={
	["osu!"]=0;osu=0;std=0;
	taiko=1;["osu!taiko"]=1;tk=1;
	ctb=2;["osu!ctb"]=2;catch_the_beat=2;catchthebeat=2;catch=2;
	mania=3;["osu!mania"]=3;["o!m"]=3;
}

--------------------------------------------------------------------------------
-- Configuration variables
--------------------------------------------------------------------------------
local cfg={
--------------------------------------------------------------------------------
-- Api key file
--------------------------------------------------------------------------------
	f_apiKey="./APIKEY"; -- file api key is contained in.
--------------------------------------------------------------------------------
-- Request throttling intervals
--------------------------------------------------------------------------------
	b_i=20; -- pause after b_i requests have been made
	b_l=10; -- pause length (`sleep` arg)
--------------------------------------------------------------------------------
-- Request variables
--------------------------------------------------------------------------------
	r_l=20; -- amount of top plays to be requested.
	r_m="std";  -- request gamemode
	r_s="u";-- usernames or IDs
--------------------------------------------------------------------------------
-- Check variables
--------------------------------------------------------------------------------
	c_Checks="all";          -- Checks to perform, see keys in table _checks;
	c_ppGap_maxgap=50;         -- Maximum pp difference between two top plays.
	c_ppSpr_spreadleniency=10; -- ((r_l/2)th play - c_spreadleniency) < (avg. pp of r_l top plays) < ((r_l/2)th top play - spreadleniency)
	c_pcMin_minplaycount=8000; -- Minimum amount of plays
	c_rrChk_highboundary=20000;-- Upper rank boundary
	c_rrChk_lowboundary=70000; -- Lower rank boundary
	c_rrChk_margin=2000;       -- Allowable rank margin
--------------------------------------------------------------------------------
	_=0; -- Throwaway (prevent argparse from dying).
}
--------------------------------------------------------------------------------
-- The Reports table stores information on users- each entry (with key=userID)
-- is a table with:
--		the user's name
--		a URL to the user's account
--		a table containing reports about the user
--------------------------------------------------------------------------------
Reports={};

function new_player(player)
	Reports[player.user_id]={
		name=player.username,
		url=("https://osu.ppy.sh/u/%s"):format(player.user_id),
		reports={};
	}
end

--------------------------------------------------------------------------------
-- Report function takes arguments with information about a given check.
-- It then automatically compiles and allocates a new report for the player.
--------------------------------------------------------------------------------
function report(player,check,description,...)
	local player=player;
	local check=check or "debug";
	local description=description or "an error has occurred- faulty report args.";
	local description=description:format(unpack({...}));

	-- Allocate new entry for player.
	if (not Reports[player.user_id]) then new_player(player); end

	-- Return a compiled report.
	Reports[player.user_id].reports[#Reports[player.user_id].reports+1]={
		description=description;
		check=check;
	}
end

--------------------------------------------------------------------------------
-- Print all reports.
--------------------------------------------------------------------------------
do
-- Mold to slot variables into
local reportmold=[[

		report #%s {
		  failed check: %s
		  description: %s
		}]];

	function compile_reports(player)
		-- Allocate output string.
		local outstring="{"

		-- Go over the reports and put them into a string.
		for n,report in pairs(Reports[player.user_id].reports) do
			outstring=outstring..(
				reportmold:format(
					n,
					report.check,
					report.description
				)
			)
		end

		-- Return output string.
		return outstring.."\n\t}"
	end

--------------------------------------------------------------------------------
-- Prints general formatted information about the player to stdout.
--------------------------------------------------------------------------------
-- Mold to slot variables into.
local playermold=[[Player: %s [%s] from %s {
	URL: https://osu.ppy.sh/u/%s
	rank: pp(%s); rank(%s); country(%s);
	score: ranked(%s); total(%s); accuracy(%2f%%);
	ranks: SS+(%s); SS(%s); S+(%s); S(%s); A(%s);
	playcount: %s;

	reports: %s %s
}
]];
	function print_player(player)
		local report_amount,report_formatted;
		-- If reports exist for player, compile them.
		if Reports[player.user_id] then
			report_formatted,report_amount=compile_reports(player);
		end


		-- Format and return string.
		return playermold:format(
			player.username,player.user_id,player.country,
			player.user_id,
			player.pp_raw,player.pp_rank,player.pp_country_rank,
			player.ranked_score,player.total_score,player.accuracy,
			player.count_rank_ssh,player.count_rank_ss,player.count_rank_sh,player.count_rank_s,player.count_rank_a,
			player.playcount,
			(report_amount or "0"),(report_formatted or "{}")
		)
	end

local mold_nonexist=[[
Player: %s does not exist {
	error: "zero result for query general playerinfo '%s'"
}
]]
	function print_nonexist(name)
		return mold_nonexist:format(name,name)
	end

local mold_notopplays=[[
Player: %s does not have any top plays {
	error: "player '%s' has no top plays"
}
]]
	function print_notopplays(name)
		return mold_nonexist:format(name,name)
	end
end

--------------------------------------------------------------------------------
-- pp tally function
--------------------------------------------------------------------------------
-- Function that returns a table with just pp scores, and the total pp.
-- Takes the `player.top` subtable in a player response.
--
-- Results are memoized because of how frequently this function might be called.
--------------------------------------------------------------------------------
do
	-- Memoization table
	local results=setmetatable({},{__mode="k"});

	function pp_tally(plays)
		-- If result has already been memoized, return now.
		if results[plays] then return results[plays] end;

		-- Keep track of both total pp and pp history.
		local pp={};
		local total_pp=0;

		-- Start counting.
		for num,play in pairs(plays) do
			-- Allocate entries + add pp count to total pp.
			pp[num]=play.pp;
			total_pp=total_pp+play.pp;
		end

		-- memoize results and return.
		results[plays]={pp,total_pp};

		return results[plays];
	end
end

--------------------------------------------------------------------------------
-- Checks
--------------------------------------------------------------------------------
-- Individual checks that can be performed on a given user.
--
-- Checks create a report when suspicious behaviour is detected.
--------------------------------------------------------------------------------
Checks={};

--------------------------------------------------------------------------------
-- All checks
--------------------------------------------------------------------------------
-- Perform all checks other than this check itself.
--------------------------------------------------------------------------------
function Checks.all(player,cfg)
	-- Execute every check except "All"
	for k,v in pairs(Checks) do
		if (k~="all") then
			v(player,cfg)
		end
	end
end

--------------------------------------------------------------------------------
-- pp gap check
--------------------------------------------------------------------------------
-- Checks whether there are any suspiciously large gaps between two plays.
--------------------------------------------------------------------------------
function Checks.pp_gap(player,cfg)
	-- Allocate tables containing all of the pp scores, and a total pp count.
	local pp_data=pp_tally(player.top);
	-- The amount of pp the last play had.
	local last=pp_data[1][1];

	-- Go over each top play.
	for num,amount in pairs(pp_data[1]) do
		-- If the gap between two plays is higher than the maximum allowed gap,
		-- complain.
		if (math.abs(last - amount) > cfg.c_ppGap_maxgap) then
			report(
				player,
				"pp_gap",
				("Plays of this player exceed max acceptable gap.\n\t\t\t%s: %s (%s)\n\t\t\t%s: %s"),
				num-1,pp_data[1][num-1],(pp_data[1][num-1]-amount),num,amount
			)
		end
		last=amount;
	end
end

--------------------------------------------------------------------------------
-- pp spread check
--------------------------------------------------------------------------------
-- Checks whether the distribution of pp is relatively equal (not skewed towards)
-- one direction.
--------------------------------------------------------------------------------
function Checks.pp_spread(player,cfg)
	-- Allocate tables containing all of the pp scores, and a total pp count.
	local pp_data=pp_tally(player.top);

	-- Average pp
	local numspread=(pp_data[2]/#player.top);
	-- Acceptable threshold
	local thresh=(pp_data[1][(#player.top)/2]+pp_data[1][((#player.top)/2)+1])/2

	if not (((thresh-cfg.c_ppSpr_spreadleniency) < (numspread)) and ((numspread) < (thresh+cfg.c_ppSpr_spreadleniency))) then
		report(
			player,
			"pp_spread",
			("Unnaceptable spread for player: skewed distribution\n\t\t\tequation (%s < %s < %s) does not hold true"),
			thresh-cfg.c_ppSpr_spreadleniency,numspread,thresh+cfg.c_ppSpr_spreadleniency
		)
	end
end

--------------------------------------------------------------------------------
-- Minimum playcount check
--------------------------------------------------------------------------------
-- Player must have over x plays, lest they be deemed suspicious.
--------------------------------------------------------------------------------
function Checks.min_playcount(player,cfg)
	if ( tonumber(player.playcount) <= cfg.c_pcMin_minplaycount ) then
		report(
			player,
			"min_playcount",
			("Playcount does not exceed minimum\n\t\t\t%s <= %s"),
			player.playcount,cfg.c_pcMin_minplaycount
		)
	end
end

--------------------------------------------------------------------------------
-- Encode to uri.
--------------------------------------------------------------------------------
-- stolen: https://gist.github.com/ignisdesign/4323051
--------------------------------------------------------------------------------
function url_encode(str)
   if (str) then
      str = string.gsub (str, "\n", "\r\n")
      str = string.gsub (str, "([^%w ])",
         function (c) return string.format ("%%%02X", string.byte(c)) end);
      str = string.gsub (str, " ", "+");
   end
   return str;
end

--------------------------------------------------------------------------------
-- Request functions
--------------------------------------------------------------------------------
-- Simply encodes url and then requests the `amount` of topscores for user
-- `user`, mode `mode`, 
--------------------------------------------------------------------------------
function request_topscores(apikey,user,amount,type,mode)
	local user=url_encode(user);
	local request_url = (
		"https://osu.ppy.sh/api/get_user_best?k=%s&u=%s&m=%s&limit=%s&type=%s"
	):format(
		apikey, user, mode, amount, type
	);

	-- Make a request. If the request fucked up (bad request, no auth, etc.)
	-- then just get angry and return 'false' instead of the ""result""
	local result,code,header,response=http.request(request_url);
	if (code ~= 200) then
		return false,code,header,response;
	else
		return result,code,header,response;
	end
end
--------------------------------------------------------------------------------
-- Simply encodes url and then requests general information about the player.
--------------------------------------------------------------------------------
function request_playerdata(apikey,user,type,mode)
	local user=url_encode(user);
	local request_url = (
		"https://osu.ppy.sh/api/get_user?k=%s&u=%s&m=%s&type=%s"
	):format(
		apikey,user,mode,type
	)

	local result,code,header,response = http.request(request_url);
	if (code ~= 200) then
		return false,code,header,response;
	else
		return result,code,header,response;
	end
end
--------------------------------------------------------------------------------
-- Very simple argument parsing
--------------------------------------------------------------------------------
function parse_args (args)
	-- Store the last specified flag.
	local last="_";

	-- Iterate over each argument
	for n,flag in pairs(args) do
		-- If it starts with '--' then it must be a flag:
		if (flag:find("^%-%-")) then
			-- Remove leading hyphens.
			flag=flag:sub(3)

			-- Sanity check before assigning.
			assert(cfg[flag],("invalid option '%s'"):format(flag))
			last=flag;
		-- Else it's an argument:
		else
			-- Interpolate into a number if possible.
			flag=(tonumber(flag) or flag);

			-- If the type of the given argument doesn't match up
			-- with the type of the default argument, then throw
			-- an error:
			assert(
				type(flag) == type(cfg[last]),
				("wrong argument type for '%s'. Expected %s, got %s"):format(
					last,type(cfg[last]),type(flag)
				)
			);

			-- Set the variable otherwise.
			cfg[last]=flag;
		end
	end
end

--------------------------------------------------------------------------------
-- Actual execution
--------------------------------------------------------------------------------
-- Parse arguments
parse_args({...});
-- Get API Key
cfg.apiKey=get_apikey(cfg.f_apiKey);

-- Gamnemode sanity check
assert(Modes[cfg.r_m],("no such osu!gamemode '%s'"):format(cfg.r_m)); cfg.r_m=Modes[cfg.r_m];
-- Searchmode sanity check
assert((cfg.r_s=="u") or (cfg.r_s=="id"),("invalid search type: expected 'u' or 'id', got '%s'"):format(cfg.r_s));
-- Checks sanity check
local checklist=cfg.c_Checks; cfg.c_Checks={};
assert(checklist:gsub("[,%s]","") ~= "",("no checks specified in checklist"));

for check in (checklist:gsub(",*$",",")):gmatch("([^,]+),") do
	assert(Checks[check],("no such check '%s'"):format(check));
	cfg.c_Checks[#cfg.c_Checks+1]=check;
end

-- Get names of players to check from stdin.
local names=get_names();

--------------------------------------------------------------------------------
-- Go over the list of names to-be-checked.
--------------------------------------------------------------------------------
local player;

for _,name in pairs(names) do
	-- Retrieve general player information:
	local result,code,headers,response=
		request_playerdata(
			cfg.apiKey, -- api key
			name,       -- user
			cfg.r_s,    -- type of argument
			cfg.r_m     -- gamemode
		)

	-- Make sure no errors were raised.
	assert(result,("non-OK response: %s"):format(tostring(response)));

	-- Decode JSON data
	local player = JSON:decode(result)[1];

	-- Ensure JSON wasn't empty:
	if (not player) then
		print(print_nonexist(name))
	else --no 'continue' statement :(
		-- Retrieve player top plays.
		local result,code,headers,response=
			request_topscores(
				cfg.apiKey,
				name,
				cfg.r_l,
				cfg.r_s,
				cfg.r_m
			)

		-- Make sure no errors were raised.
		assert(result,("non-OK response: %s"):format(tostring(response)));

		-- Decode JSON data
		player.top = JSON:decode(result);

		-- Ensure JSON wasn't empty:
		if (not player.top) then
			print(print_notopplays(name))
		else
			-- Perform all appropriate checks:
			for _,check in pairs(cfg.c_Checks) do
				Checks[check](player,cfg);
			end

			-- Print info on player:
			print(print_player(player))
		end
	end

	-- Take a break if necessary.
	if ( (_ % cfg.b_i) == 0) then
		os.execute(("sleep %s"):format(cfg.b_l))
	end
end