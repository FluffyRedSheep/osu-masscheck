# osu!masscheck
Lua script used to both download information on players, and perform automated cheating-related checks.
Initially commissioned by **Redavor** for use in tournaments hosted by the _Rapid Monthly osu! Tournament_ group.

Tested and confirmed functional using Lua 5.1.
Requires [luasocket](https://luarocks.org/modules/luarocks/luasocket), and [json-lua](https://luarocks.org/modules/jiyinyiyong/json-lua)

You must request an osu!API key [here](https://osu.ppy.sh/p/api). By default, `osu!masscheck` reads from `./APIKEY` for the API key.
To alter this, see below.

## Usage
Execution is simple: `cat file_with_list_of_names_to_check | lua main.lua [options]` will output to `stdout` a full listing of names. (this might take a while, as individual requests take a short while, coupled with the fact requests are throttled.)

The `options` may be a continuous sequence of flags (`--flag_name`) and arguments (`20`, `"a"`, etc.)

## Supported options
### General options
```
--f_apiKey (./APIKEY)         - the file that the API key is stored in by default

--b_i (10)				      - amount of users to request info from before pausing
--b_l (10)                    - how long to pause (direct argument to 'sleep')

--r_l (20)                    - amount of top plays to request for any given player
--r_m (std)                   - which gamemode to request info for
--r_s (u)                     - whether the list fed through stdin describes names ('u') or user IDs ('id')

--c_Checks (all)              - comma-delimited list of which checks to perform (see below)
```
### Check-specific options
**pp_gap**
```
--c_ppGap_maxgap (50)         - maximum pp gap between two top plays
```
**pp_spread**
```
--c_ppSpr_spreadleniency (10) - maximum allowed pp spread
```
**min_playcount**
```
--c_pcMin_minplaycount (8000) - minimum amount of plays a player must have on their profile
```
**rank_range** (TBD, unused)
```
--c_rrChk_highboundary (2000) - maximum rank players can have
--c_rrChk_lowboundary (7000)  - minimum rank players must have
--c_rrChk_margin (2000)       - how many ranks of margin are granted to the player
```
## Checks
### pp_gap
Goes through the requested players' top plays, and raises an error if the pp difference between two plays exceeds `c_ppGap_maxgap`
### pp_spread
Checks for inequal distribution among top plays- it takes the average pp difference between two top plays (`total pp / amount of top plays`) and then proceeds to check each individual pp increase between two plays. If a given pp gap veers off from the average by `c_ppSpr_spreadleniency` pp, then an error is raised.
### min_playcount
Playcount of a player must be **bigger** than `c_pcMin_minplaycount`, lest an error is thrown.
### rank_range (TBD)
Shall verify that a players' rank is somewhere inbetween `c_rrChk_highboundary-c_rrChk_margin` and `c_rrChk_lowboundary+c_rrChk_margin`. If this does not hold true, and error is raised.