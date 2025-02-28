;
;	plan_scripts_minxss2
;
;	This procedure will generate HYDRA scripts using pass times created by plan_satellite_pass
;
;
;	********************************************************************
;	***                                                              ***
;	***   Run this after the plan_satellite_pass.pro has been run    ***
;	***                                                              ***
;	********************************************************************
;
;	INPUT
;		station 	Option to specify Station - defaults to BOULDER
;		station_remote Option to plan stored playbacks for remote station (e.g. Fairbanks)
;		date		Option to specify date for planning 1-day stored-command load for remote station
;						date can be YYYYDOY or YYYYMMDD format
;		debug		Option to not download latest TLE while debugging this procedure
;		verbose		Option to print information while running
;
;	OUTPUT
;		old scripts are deleted and new scripts are created
;		pass plan CSV file that can be imported into MinXSS-2 log worksheet
;
;	PROCEDURE
;	1.  Read passes info created by plan_satellite_pass.pro
;	2.  Delete old scripts
;	3.	Create new scripts
;			New Scripts can include loading stored commands at the remote station
;	4.	Create CSV file of pass plans for use in MinXSS-2 Log Worksheet
;	5.  Generate set_ephemeris_latest.prc HYDRA script
;
;	HISTORY
;		2017-Apr-02  T. Woods	Original Code based on minxss_satellite_pass.pro
;		2018-Nov-29  T. Woods   Updated for new file paths for Stations
;

pro plan_scripts_minxss2, station, station_remote, date, debug=debug, verbose=verbose

;
;	configure inputs
;
if (n_params() lt 1) then station = 'Fairbanks'
station_caps = strupcase(station)
if (n_params() lt 2) then station_remote = ''
station_remote_caps = strupcase(station_remote)

stations_valid = [ 'Boulder', 'Fairbanks', 'Parker' ]
valid_1 = 0
valid_2 = 0
for k=0,n_elements(stations_valid)-1 do begin
	stations_valid_caps = strupcase(stations_valid[k])
	if (strlen(station_caps) gt 1) and (strpos(stations_valid_caps,station_caps) eq 0) then begin
		valid_1 = 1
		station = stations_valid[k]
		station_caps = stations_valid_caps
	endif
	if (strlen(station_remote_caps) gt 1) and (strpos(stations_valid_caps,station_remote_caps) eq 0) then begin
		valid_2 = 1
		station_remote = stations_valid[k]
		station_remote_caps = stations_valid_caps
	endif
endfor
if (valid_1 eq 0) then begin
	print, 'ERROR: valid station name is needed to run plan_scripts_minxss2.pro !'
	return
endif

if keyword_set(debug) then verbose = 1
if keyword_set(verbose) then begin
	print, 'MinXSS-2 scripts are being generated for ',station_caps,' station...'
	if (valid_2 eq 1) then print, '   and for ',station_remote_caps,' remote station.'
endif

;
;	Get TLE path
;  		default is to use directory $TLE_dir
;
;  slash for Mac = '/', PC = '\'
;  File Copy for Mac = 'cp', PC = 'copy'
if !version.os_family eq 'Windows' then begin
    slash = '\'
    file_copy = 'copy '
    file_delete = 'del /F '
endif else begin
    slash = '/'
    file_copy = 'cp '
    file_delete = 'rm -f '
endelse

;
;	Get path for TLE / pass time data (as created by plan_satellite_pass.pro)
;
path_name = getenv('TLE_dir')
if strlen(path_name) gt 0 then begin
  if ((strpos(path_name,slash,/reverse_search)+1) lt strlen(path_name)) then path_name += slash
endif
; else path_name is empty string
if keyword_set(verbose) then print, '*** TLE path = ', path_name

;
; Get paths for Hydra Scripts - must be in Dropbox/Hydra/MinXSS/HYDRA_FM-2_xxxxxx/Scripts/
;
dropbox_dir = getenv('Dropbox_root_dir')
if strlen(dropbox_dir) ne 0 then dropbox_dir += slash
if keyword_set(verbose) then print, '*** Dropbox path = ', dropbox_dir
station_dir = dropbox_dir + "Hydra" + slash + "MinXSS" + slash + "HYDRA_FM-2_"+station+slash
script_dir = station_dir + "Scripts" + slash
if keyword_set(verbose) then print, '*** Script path = ', script_dir
if (valid_2) then begin
  station_remote_dir = dropbox_dir + "Hydra" + slash + "MinXSS" + slash + "HYDRA_FM-2_"+station_remote+slash
  script_remote_dir = station_remote_dir + "Scripts" + slash
  if keyword_set(verbose) then print, '*** Remote Script path = ', script_remote_dir
endif

;
;	1.  Read pass information for this station
;			Read Remote Station pass info first
;
if (strlen(station_remote) gt 1) then begin
	save_path = path_name + station_remote_caps + slash
	save_name2 = 'passes_latest_'+station_remote_caps+'.sav'
	if keyword_set(verbose) then print, 'Restoring "passes" data from ', save_path+save_name2
	restore, save_path+save_name2   ;  passes data structure restored (read)
	passes_remote = passes 			; save "passes" as different name
endif

save_path = path_name + station_caps + slash
save_name1 = 'passes_latest_'+station_caps+'.sav'
if keyword_set(verbose) then print, 'Restoring "passes" data from ', save_path+save_name1
restore, save_path+save_name1   ;  passes data structure restored (read)

;
;	generate support data for the passes data structure
;
number_passes = n_elements(passes)
if (number_passes lt 2) then begin
	print, 'ERROR: "passes" data structure is not valid !'
	return
endif

pass_date_str = strarr(number_passes)
pass_hour = fltarr(number_passes)
for k=0,number_passes-1 do begin
	caldat, passes[k].start_jd, month, day, year, hh, mm, ss
	; pass_date_str[] is needed for /auto_pass option below
	pass_date_str[k] = string(long(year),format='(I04)') + string(long(month),format='(I02)')+$
						string(long(day),format='(I02)') + '_' + $
						string(long(hh),format='(I02)') + string(long(mm),format='(I02)')
	pass_hour[k] = hh + mm/60. + ss/3600.
endfor

;
;	get "date" for stored-command load for the remote station
;			date can be YYYYDOY or YYYYMMDD format
;
if (strlen(station_remote) gt 1) then begin
	bad_date = 1
	if n_params() ge 3 then begin
		if (date gt 20180101L) then begin
			date_str = strtrim(long(date),2)
			year = long(strmid(date_str,0,4))
			month = long(strmid(date_str,4,2))
			day = long(strmid(date_str,6,2))
			date_jd = ymd2jd(year, month, day)
			date_yd = jd2yd(date_jd)
			bad_date = 0
		endif else if (date lt 2030001L) and (date gt 2018001L) then begin
			date_yd = date
			date_jd = yd2jd(date_yd)
			bad_date = 0
		endif
	endif
	; else have user select which date
	if (bad_date ne 0) then begin
		jd1_min = min(passes.start_jd) + 1.  ; add extra day so uplink can happen
		jd2_min = min(passes_remote.start_jd)
		if (jd2_min lt jd1_min) then jd2_min = jd1_min
		jd1_max = max(passes.start_jd)
		jd2_max = max(passes_remote.start_jd)
		if (jd2_max lt jd1_min) then begin
			print, 'ERROR:  Remote Station pass times do not overlap with Uplink Station pass times !'
			return
		endif
		jd1_min -= 1.  ; restore back to first day
		caldat, jd1_min, month, day, year, hh, mm, ss
		yd1_min = jd2yd(jd1_min)
		ymd1_str = string(long(year),format='(I04)') + '/' + string(long(month),format='(I02)')+$
						'/' + string(long(day),format='(I02)')
		yd1_str = strtrim(long(yd1_min),2)
		; +++++ TO DO - ask User for date for stored-command load
	endif
	caldat, date_jd, month, day, year, hh, mm, ss
	yd_str = strtrim(long(date_yd),2)
	doy = long(strmid(yd_str,4,3))
	print, 'Planning stored-command load at ', station_remote_caps, $
		' for ', strtrim(year,2), '-', strtrim(month,2), '-', strtrim(day,2), $
		' (DOY ', strtrim(doy,2), ')'
	; +++++ TO DO - ask User for primary station pass time for uplinking the stored-command load

	; +++++ TO DO - make stored-command load script for the primary station

	stop, 'DEBUG: ready to exit after making stored-command load script ...'
endif

;
;	ELSE Plan Pass Scripts for the primary station
;
;	2.  Delete old scripts
;	3.	Create new scripts
;
elev_ranges = [ [0.,2.], [2, 10], [10, 90] ]
script_names = [ 'pass_do_nothing.prc', 'route_realtime.prc', 'playback2_last_24_hours.prc' ]
script_plan_names = [ 'EL<2: Do Nothing', '2<EL<10: Route Data', 'Playback Last 24 Hours' ]
;  Fairbanks doesn't have mountains to mask out
if (station_caps eq 'FAIRBANKS') then begin
  elev_ranges = [ [0.,2.], [2, 5], [5, 90] ]
  script_plan_names = [ 'EL<2: Do Nothing', '2<EL<5: Route Data', 'Playback Last 24 Hours' ]
endif
; Boulder has special plans for 2019 Recovery of MinXSS-2
if (station_caps eq 'BOULDER') then begin
  DO_MINXSS2_RECOVERY_SCRIPTS = 1
  if (DO_MINXSS2_RECOVERY_SCRIPTS ne 0) then begin
    day_script_names = [ 'pass_do_nothing.prc', 'pass_do_nothing.prc', 'route_realtime.prc' ]
    ;  ATTEMPT TO DO HARD RESET WHEN IN THE DARK IN BOULDER
    night_script_names = [ 'pass_do_nothing.prc', 'pass_do_nothing.prc', 'auto_hard_reset.prc' ]
  endif
endif
  
num_ranges = n_elements(script_names)

;
;	first delete the files that overlap with these new passes
;
scripts_template_dir = script_dir + 'scripts_auto_template' + slash
scripts_run_dir = script_dir + 'scripts_to_run_automatically' + slash
first_file = pass_date_str[0]
last_file = pass_date_str[number_passes-1]
search_name = '20*.prc'
file_list = file_search( scripts_run_dir, search_name, count=count )
del_count = 0L
flare_count = 0L
doy_count = 0L
if (count gt 0) then begin
  for k=0,count-1 do begin
	pslash = strpos( file_list[k], slash, /reverse_search )
	if (pslash gt 0) then file_date = strmid( file_list[k], pslash+1, 13 ) $
	else file_date = strmid( file_list[k], 0, 13 )
	;  don't delete flare or DOY playback scripts though
	upcasefile = strupcase(file_list[k])
	pflare = strpos( upcasefile, 'FLARE' )
	pdoy = strpos( upcasefile, 'DOY' )
	pcustom = strpos( upcasefile, 'CUSTOM' )
	if (pflare ge 0) then flare_count += 1
	if (pdoy ge 0) then doy_count += 1
	if (file_date ge first_file) and (file_date le last_file) and (pflare lt 0) $
			and (pdoy lt 0) and (pcustom lt 0) then begin
		del_count += 1
		del_cmd = file_delete + '"' + file_list[k] + '"'
		spawn, del_cmd, exit_status=status
	endif
  endfor
endif
print, '***** Script files deleted: ' + strtrim(del_count,2)
if (flare_count gt 0) then print, '***** Script FLARE files saved: ' + strtrim(flare_count,2)
if (doy_count gt 0) then print, '***** Script DOY files saved: ' + strtrim(doy_count,2)
if keyword_set(debug) then stop, 'DEBUG: verify old Scripts files have been deleted...'

;
;	then copy the template scripts into the AUTO script directory based on elevation
;		 0-12 deg EL =  pass_do_nothing.prc
;		12-24 deg EL =  adcs_route_realtime.prc
;		24-90 deg EL =  playback_last_48_hours.prc
;
; elev_ranges = [ [0.,12], [12, 24], [24, 90] ]
;  Updated ranges on 7/28/2016 T. Woods
;  NOTE: see the elev_ranges and script_names definitions ABOVE
; elev_ranges = [ [0.,15], [15, 30], [30, 90] ]
; script_names = [ 'pass_do_nothing.prc', 'adcs_route_realtime.prc', 'playback_last_48_hours.prc' ]
; num_ranges = n_elements(script_names)
;
jd_now = systime( /julian ) + 6./24.D0  ; also convert MST to UT
num_create = 0L
start_date = '????'
match_name = 'MINXSS2'

for k=0L, number_passes-1 do begin
  ; only create pass scripts for the future
  if (passes[k].start_jd gt jd_now) and (strpos(passes[k].satellite_name,match_name) eq 0) then begin
	ii = 0L
	for jj=1,num_ranges-1 do begin
		if (passes[k].max_elevation gt elev_ranges[0,jj]) and $
			(passes[k].max_elevation le elev_ranges[1,jj]) then begin
		  ii = jj
		endif
	endfor
	; Note that pass_date_str[] was created above after reading the passes data
	if (DO_MINXSS2_RECOVERY_SCRIPTS ne 0) then begin
	   ; SPECIAL RECOVERY OPTION FOR MINXSS-2 WITH SELECTION OF SCRIPT BASED ON DAY OR NIGHT TIME FOR PASS
	   ; pass_hour is calculated as hours in UT on pass day while parsing the PASS data file
	   ; NIGHT = 4 UT (10 PM MDT or 9 PM MST) to 11 UT (5 AM MDT or 4 AM MST)
	   if (pass_hour[k] ge 4.0 and pass_hour[k] le 11.0) then begin
	     script_names = night_script_names
	   endif else begin
	     script_names = day_script_names
	   endelse
	endif
	new_file = pass_date_str[k] + 'UT_' + script_names[ii]
	template_file = script_names[ii]
	;  COPY template file TO NEW FILE
	copy_cmd = file_copy + '"' + scripts_template_dir+template_file + '" "' + $
				scripts_run_dir+new_file + '"'
	spawn, copy_cmd, exit_status=status
	if (num_create eq 0) then start_date = pass_date_str[k] + 'UT'
	num_create += 1L
  endif
endfor
print, '***** Auto Pass Scripts created for ' + strtrim(num_create,2) + ' passes.'
print, ' '
if keyword_set(debug) then $
	stop, 'DEBUG: Verify new scripts files in scripts_to_run_automatically/ ...'

;
;	4.	Create CSV file of pass plans for use in MinXSS-2 Log Worksheet
;
if (num_create gt 1) then begin
	csv_path = path_name + station_caps + slash
	csv_name3 = 'plans_latest_MINXSS2.csv'
	if keyword_set(verbose) then print, 'Saving "pass plan" CSV file to ', csv_path+csv_name3
	openw, lun, csv_path+csv_name3, /get_lun
	printf, lun, 'MinXSS-2 CubeSat Pass Default Plans that start at ' + start_date
	csv_header = 'Orbit#, Start Time, End Time, Duration Minutes, Peak Elevation, In Sunlight, Script Plan'
	printf, lun, csv_header
	for k=0L, number_passes-1 do begin
	  ; only create pass scripts for the future
  	  if (passes[k].start_jd gt jd_now) and (strpos(passes[k].satellite_name,match_name) eq 0) then begin
  	  	  ; +++++ TO DO (fix)
		  ; pass_num_str = string( pass_orbit_number[k], format='(I6)')
		  pass_num_str = ' TBD '
		  caldat, passes[k].start_jd, month, day, year, hh, mm, ss
		  start_str = strmid( timestamp( year=year, month=month, day=day, hour=hh, min=mm, sec=ss ), 0, 19)+'UT'
		  caldat, passes[k].end_jd, month, day, year, hh, mm, ss
		  end_str = strmid( timestamp( year=year, month=month, day=day, hour=hh, min=mm, sec=ss ), 0, 19)+'UT'
		  duration_str = string(passes[k].duration_minutes, format='(F8.2)')
		  elevation_str = string( passes[k].max_elevation, format='(F8.2)')
		  if (passes[k].sunlight ne 0) then sun_str = 'YES' else sun_str='eclipse'
		  pass_str = pass_num_str + ', ' + start_str + ', ' + end_str + ', ' + duration_str + ', ' + $
				elevation_str + ', ' + sun_str
		  ii = 0L
		  for jj=1,num_ranges-1 do begin
			if (passes[k].max_elevation gt elev_ranges[0,jj]) and $
				(passes[k].max_elevation le elev_ranges[1,jj]) then begin
				ii = jj
			endif
		  endfor
		  pass_str = pass_str + ', ' + script_plan_names[ii]
		  printf, lun, pass_str
	  endif
	endfor
	printf, lun, ' '
	printf, lun, 'This table was generated by plan_scripts_minxss2.pro on ' + systime(/utc)
	printf, lun, ' '
	close, lun
	free_lun, lun

endif

;
; 5. generate set_ephemeris_latest.prc HYDRA script
;
make_set_ephemeris_script, /latest

if keyword_set(debug) then stop, 'DEBUG plan_scripts_minxss2 results ...'

return
end

