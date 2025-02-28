;+
; NAME:
;   minxss_make_level1_xminute.pro
;
; PURPOSE:
;   Read a data product and make x minute averages and store the data in a structure
;
;   This will process L0D raw counts from X123 into irradiance units and in x-minute averages.
;   It also calculates the XP background subtracted data
;
; INPUTS:
;   minxsslevel1_x123_time_structure [structure]:      The time array from minxsslevel1.x123.time
;   minxsslevel1_x123_dark_time_structure [structure]: The time array from minxsslevel1.x123_dark.time
;   minxsslevel1_xp_time_structure [structure]:        The time array from minxsslevel1.xp.time
;   minxsslevel1_xp_dark_time_structure [structure]:   The time array from minxsslevel1.xp_dark.time
;
; OPTIONAL INPUTS:
;   fm [integer]:               Flight Model number 1 or 2 (default is 1)
;   low_limit [float]:          Option to change limit on selecting low energy counts for good X123 spectra. Default is 7.0
;   x_minute_average [integer]: Set to the number of minutes you want to average. Default is 1.
;   start_time_cd_array [??]:   Not sure what this is for
;   end_time_cd_array [??]:     Not sure what this is for
;   version [string]: Software/data product version to store in filename and internal anonymous structure. Default is '2.0.0'.
;   cal_version [string]: Calibration version to store in internal anonymous structure. Default is '2.0.0'.
;
; KEYWORD PARAMETERS:
;   VERBOSE: Set this to print processing messages
;   DEBUG:   Set this to trigger stop points for debugging
;
; OUTPUTS:
;   IDL saveset to disk
;
; OPTIONAL OUTPUTS:
;   None
;
; COMMON BLOCKS:
;   None
;
; RESTRICTIONS:
;   Uses the library routines for converting time (GPS seconds, Julian date, etc.)
;   Uses Chris Moore's irradiance conversion code for X123
;   Need the functions (minxss_x123_correct_deadtime.pro, minxss_X123_mean_count_rate_uncertainty.pro, minxss_XP_mean_count_rate_uncertainty.pro, minxss_XP_signal_from_X123_signal.pro, minxss_x123_invert_count_to_photon_estimate.pro, minxss_X123_be_photoelectron_si_escape_count_correction.pro)
;
; PROCEDURE:
;   1. Read the MinXSS Level 0D mission-length file
;   2. Select (filter) the data for good (valid) data
;      not in eclipse by at least one minute, radio flag is greater than 1,
;      low energy counts are below the low_limit
;   3. Choose the timeframe of the data to be considered
;   4. First order correction for deadtime
;   5. Average the data over x-minute intervals, make irradiance values calculate XP background subtracted data and compare to X123 estimates
;   6. Make meta-data for Level 1
;   7. Save the Level 1 results (mission-length file)
;
;+
PRO minxss_make_level1_xminute, fm=fm, x_minute_average=x_minute_average, start_time_cd_array=start_time_cd_array, end_time_cd_array=end_time_cd_array, low_limit=low_limit, version=version, cal_version=cal_version, $
                                minxsslevel1_x123_time_structure=minxsslevel1_x123_time_structure, minxsslevel1_x123_dark_time_structure=minxsslevel1_x123_dark_time_structure, minxsslevel1_xp_time_structure=minxsslevel1_xp_time_structure, minxsslevel1_xp_dark_time_structure=minxsslevel1_xp_dark_time_structure, $
                                VERBOSE=VERBOSE, DEBUG=DEBUG

  seconds_per_day = 60.0*60.0*24.0
  ; Defaults
  if keyword_set(debug) then verbose=1

  if fm EQ !NULL then fm = 1
  fm_str = strtrim(fm,2)
  if keyword_set(verbose) then begin
    print, "minxss_make_level1 is processing data for FM " + fm_str
    print, '   START at ', systime()
  endif
  IF version EQ !NULL THEN version = '2.0.0'
  IF cal_version EQ !NULL THEN cal_version = '2.0.0'

  if fm eq 1 then LOW_LIMIT_DEFAULT = 7.0 $
  else LOW_LIMIT_DEFAULT = 7.0  ; for FM-2 ???
  if not keyword_set(low_limit) then low_limit = LOW_LIMIT_DEFAULT
  if keyword_set(verbose) then print, '     low_limit = ', low_limit
  ;
  ; 1. Read the MinXSS Level 0D mission-length file
  ;
  ddir = getenv('minxss_data')
  if strlen(ddir) lt 1 then begin
    print, '*** ERROR finding MinXSS data, you need to define $minxss_data environment variable.'
    return
  endif
  fmdir = ddir + path_sep() + 'fm' + fm_str + path_sep()
  indir = fmdir + 'level0d' +  path_sep()
  infile = 'minxss' + fm_str + '_l0d_mission_length_v' + version + '.sav'
  if keyword_set(verbose) then print, '     Reading L0D data'
  restore, indir+infile    ; variable is MINXSSLEVEL0D


  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;for testing purposes just run the ~ 1,000 entries
  ; minxsslevel0d_old = minxsslevel0d
  ; minxsslevel0d = minxsslevel0d[4E3:5E3]
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;
  ; 2. Select (filter) the data for good (valid) data
  ;   not in eclipse by at least one minute, radio flag is less than 1,
  ;   low energy counts are below the low_limit, and ADCS mode is Fine-Ref(1)
  ;
  sp_sec = (minxsslevel0d.time.jd - yd2jd(2016001.D0))*24.D0*3600.  ; seconds since Jan 1, 2016
  ; sp = count rate
  sp = float(minxsslevel0d.x123_spectrum)
  ; raw total counts in the integration time
  sp_counts = sp
  num_sci = n_elements(minxsslevel0d)
  ; convert to counts per sec (cps) with smallest time
  ; Note that Version 1 used x123_live_time instead of x123_accum_time
  for ii=0,num_sci-1 do sp[*,ii] = sp[*,ii] / (minxsslevel0d[ii].x123_accum_time/1000.)

  fast_count = minxsslevel0d.x123_fast_count / (minxsslevel0d.x123_accum_time/1000.)
  fast_limit = 3.E4  ; New version 2 value.  Version 1 values was 1.E5 for FM-1
  if fm eq 2 then fast_limit = 3.E4   ; ??? assume same as FM-1
  slow_count = minxsslevel0d.x123_slow_count / (minxsslevel0d.x123_accum_time/1000.)
  new_low_limit = slow_count * 0.006 > low_limit   ; Version 2 improved low_limit for lowcnts check
  if fm eq 2 then new_low_limit = slow_count * 0.006 > low_limit  ; ??? FM-2 may need different function

  sps_sum = total(minxsslevel0d.sps_data_sci[0:3],1) / float(minxsslevel0d.sps_xp_integration_time)
  sps_sum_sun_min = 280000.   ; June 2016 it is 310K; this  allows for 1-AU changes and 5% degradation

  ; exclude spectra with radio on (flag > 1), not in sun, and high low counts
  lowcnts = total( sp[20:24,*], 1 )
  peakcnts = total( sp[36:40,*], 1 )
  PEAK_SLOPE_DEFAULT = 3.0
  lowlimit = 4.0    ; M5 Flare is lt 20
  slow_count_min = lowlimit
  slow_count_max = fast_limit

  ; X123_swith on flag, 1 = on and 0 is off
  x123_switch_flag = 0.0

  ; Science mode check, science_mode_flag = 4.0
  science_mode_flag_threshold = 3.0

  ; get Counts for the Fe XXV emission line
  fe_cnts = total( sp[210:250,*], 1 )
  FE_CNTS_MAX = 200.

  ; Use the input time structures from that already have filtering applied for each instrument and find where the level0d are the same
  num_sp = n_elements(minxsslevel1_x123_time_structure.JD)
  wsci = lonarr(num_sp)

  for t = 0, num_sp - 1 do begin
    wsci[t] = where(minxsslevel0d.time.JD eq minxsslevel1_x123_time_structure[t].JD)
  endfor

  num_dark = n_elements(minxsslevel1_x123_dark_time_structure.JD)
  wdark = lonarr(num_dark)

  for t = 0, num_dark - 1 do begin
    wdark[t] = where(minxsslevel0d.time.JD eq minxsslevel1_x123_dark_time_structure[t].JD)
  endfor

  if keyword_set(verbose) then print, 'Number of good L0D science packets = ',strtrim(num_sp,2), $
                                      ' out of ', strtrim(n_elements(minxsslevel0d),2)
  if (num_sp le 1) then begin
    print, '*** ERROR finding any X123 solar data'
    if keyword_set(verbose) then stop, 'DEBUG ...'
    return
  endif

  num_sp_xp = n_elements(minxsslevel1_xp_time_structure.JD)
  wsci_xp = lonarr(num_sp_xp)

  for t = 0, num_sp_xp - 1 do begin
    wsci_xp[t] = where(minxsslevel0d.time.JD eq minxsslevel1_xp_time_structure[t].JD)
  endfor

  num_sp_xp_dark = n_elements(minxsslevel1_xp_dark_time_structure.JD)
  wsci_xp_dark = lonarr(num_sp_xp_dark)

  for t = 0, num_sp_xp_dark - 1 do begin
    wsci_xp_dark[t] = where(minxsslevel0d.time.JD eq minxsslevel1_xp_dark_time_structure[t].JD)
  endfor

  ;
  ; make SPS pointing information using SCI SPS data (versus lower quality HK SPS data)
  ;
  sps_temp = minxsslevel0d.x123_board_temperature  ; reliable temperature that doesn't depend on I2C monitor
  if (fm eq 1) then begin
    ; FM-1 SPS SURF calibration result
    sps_x_factor = 3.224    ; 1/2 FOV degrees
    sps_y_factor = 3.230
    sps_gain1 = 7.11      ; fC/DN
    sps_gain2 = 6.38
    sps_gain3 = 6.51
    sps_gain4 = 5.54
    sps_dark1 = -1.623 + 0.40462*sps_temp   ; FM-1 in-flight calibration
    sps_dark2 = -1.199 + 0.42585*sps_temp   ; FM-1 in-flight calibration
    sps_dark3 = -1.602 + 0.41635*sps_temp   ; FM-1 in-flight calibration
    sps_dark4 = -1.760 + 0.44285*sps_temp   ; FM-1 in-flight calibration
  endif else begin
    sps_x_factor = 3.202    ; 1/2 FOV degrees
    sps_y_factor = 3.238
    sps_gain1 = 6.53      ; fC/DN
    sps_gain2 = 6.44
    sps_gain3 = 6.72
    sps_gain4 = 6.80
    sps_dark1 = 40. + 0.*sps_temp ; default value until have flight data
    sps_dark2 = 40. + 0.*sps_temp
    sps_dark3 = 40. + 0.*sps_temp
    sps_dark4 = 40. + 0.*sps_temp
  endelse
  SPS_SUM_LIMIT = 5000.  ; fC lower limit
  data1 = ( (minxsslevel0d.sps_data_sci[0]/minxsslevel0d.sps_xp_integration_time - sps_dark1) * sps_gain1 ) > 0.
  data2 = ( (minxsslevel0d.sps_data_sci[1]/minxsslevel0d.sps_xp_integration_time - sps_dark2) * sps_gain2 ) > 0.
  data3 = ( (minxsslevel0d.sps_data_sci[2]/minxsslevel0d.sps_xp_integration_time - sps_dark3) * sps_gain3 ) > 0.
  data4 = ( (minxsslevel0d.sps_data_sci[3]/minxsslevel0d.sps_xp_integration_time - sps_dark4) * sps_gain4 ) > 0.
  sps_sum_best = (data1 + data2 + data3 + data4) > 1.
  sps_x = ((data1 + data2) - (data3 + data4)) * sps_x_factor / sps_sum_best
  sps_y = ((data1 + data4) - (data2 + data3)) * sps_y_factor / sps_sum_best
  wbad = where(sps_sum_best lt SPS_SUM_LIMIT, numbad)
  if (numbad gt 0) then begin
    sps_x[wbad] = !VALUES.F_NAN
    sps_y[wbad] = !VALUES.F_NAN
  endif

  ;
  ; truncate L0D down to good science data (wsci)
  ;
  if keyword_set(verbose) then begin
    print, '   Processing ', strtrim(num_sp,2), ' good spectra out of ', strtrim(num_sci,2)
    if keyword_set(debug) then stop, 'DEBUG at start of irradiance conversion processing ...'
  endif

  ; add path for the calibration file
  cal_dir = getenv('minxss_data')+ path_sep() + 'calibration' + path_sep()

  if fm eq 1 then begin
    ; FM-1 values
    minxss_calibration_file = 'minxss_fm1_response_structure.sav'
    minxss_calibration_file_path = cal_dir + minxss_calibration_file
    restore, minxss_calibration_file_path
    nominal_x123_energy_bins_kev = findgen(1024) * minxss_detector_response.x123_energy_gain_kev_per_bin
    energy_bins_offset = minxss_detector_response.x123_energy_offset_kev_orbit
  endif else begin
    minxss_calibration_file = 'minxss_fm2_response_structure.sav'
    minxss_calibration_file_path = cal_dir + minxss_calibration_file
    restore, minxss_calibration_file_path
    nominal_x123_energy_bins_kev = findgen(1024) * minxss_detector_response.x123_energy_gain_kev_per_bin
    energy_bins_offset = minxss_detector_response.x123_energy_offset_kev_orbit
  endelse

  ;  save energy bins for the return
  energy_bins_kev = nominal_x123_energy_bins_kev + energy_bins_offset

  ; 3. Choose the timeframe of the data to be considered

  ; this could be keyword variable for minxss_make_level1.pro
  time_average_sec = 1.0 * 60.  ; 1-minute average is the default
  if keyword_set(x_minute_average) then begin
    x_minute_average = float(x_minute_average)
    time_average_sec = x_minute_average * 60.  ; 1-minute average
  endif
  time_average_day = time_average_sec/(seconds_per_day)


  ; set the start and end times in jd for the MinXSS-1 mission
  IF fm EQ 1 THEN BEGIN
    start_time_jd = jpmiso2jd('2016-05-16T10:05:26Z')
    end_time_jd = jpmiso2jd('2017-05-06T02:37:26Z')
  ENDIF ELSE IF fm EQ 2 THEN BEGIN
    start_time_jd = jpmiso2jd('2018-12-03T18:34:00Z')
    end_time_jd = jpmiso2jd('2019-01-07T18:35:38Z')
  ENDIF

  ; Calculate the number of total frames based on the defined start_time, end_time and x_minute_average chossen
  n_time_frames = (end_time_jd - start_time_jd)/time_average_day
  n_time_frames_long = long(n_time_frames) + 1
  x_minute_jd_time_array = (time_average_day*dindgen(n_time_frames_long)) + start_time_jd

  ; create the date to make the structure
  caldat, x_minute_jd_time_array[0], start_fill_month, start_fill_day, start_fill_year, start_fill_hour, start_fill_minute, start_fill_second
  caldat, x_minute_jd_time_array[1], end_fill_month, end_fill_day, end_fill_year, end_fill_hour, end_fill_minute, end_fill_second


  ; Define the data structures that will be filled in later
  ; minxss-1 x123 science structure
  level1_x123 = { time: minxsslevel0d[0].time, $
    interval_start_time_jd: x_minute_jd_time_array[0], $
    interval_end_time_jd: x_minute_jd_time_array[1], $
    interval_start_time_human: strtrim((start_fill_year), 1)+ '-' +strtrim((start_fill_month), 1)+ '-' +strtrim((start_fill_day), 1)+ ' ' +strtrim((start_fill_hour), 1)+ ':' +strtrim((start_fill_minute), 1)+ ':' +strmid(strtrim((start_fill_second), 1), 0, 4), $
    interval_end_time_human: strtrim((end_fill_year), 1)+ '-' +strtrim((end_fill_month), 1)+ '-' +strtrim((end_fill_day), 1)+ ' ' +strtrim((end_fill_hour), 1)+ ':' +strtrim((end_fill_minute), 1)+ ':' +strmid(strtrim((end_fill_second), 1), 0, 4), $
    flight_model: 0, $
    irradiance: fltarr(1024), $
    irradiance_uncertainty: fltarr(1024), $
    energy: fltarr(1024), $
    spectrum_cps: fltarr(1024), $
    spectrum_cps_accuracy: fltarr(1024), $
    spectrum_cps_precision: fltarr(1024), $
    spectrum_cps_stddev: fltarr(1024), $
    deadtime_correction_factor: 0.0, $
    valid_flag: fltarr(1024), $
    spectrum_total_counts: fltarr(1024), $
    spectrum_total_counts_accuracy: fltarr(1024), $
    spectrum_total_counts_precision: fltarr(1024),$
    integration_time: 0.0, $
    number_spectra: 0L, $
    x123_fast_count: 0.0, $
    x123_slow_count: 0.0, $
    sps_on: 0, $
    sps_sum: 0.0, $
    sps_x: 0.0, $
    sps_y: 0.0, $
    sps_x_hk: 0.0, $
    sps_y_hk: 0.0, $
    longitude: 0.0, $
    latitude: 0.0, $
    altitude: 0.0, $
    spacecraft_in_saa: 0.0, $
    sun_right_ascension: 0.0, $
    sun_declination: 0.0, $
    solar_zenith_angle: 0.0, $
    tangent_ray_height: 0.0, $
    earth_sun_distance: 0.0, $
    correct_au: 0.0}

  ; minxss-1 x123 dark data structure
  level1_x123_dark = { time: minxsslevel0d[0].time, $
    interval_start_time_jd: x_minute_jd_time_array[0], $
    interval_end_time_jd: x_minute_jd_time_array[1], $
    interval_start_time_human: strtrim((start_fill_year), 1)+ '-' +strtrim((start_fill_month), 1)+ '-' +strtrim((start_fill_day), 1)+ ' ' +strtrim((start_fill_hour), 1)+ ':' +strtrim((start_fill_minute), 1)+ ':' +strmid(strtrim((start_fill_second), 1), 0, 4), $
    interval_end_time_human: strtrim((end_fill_year), 1)+ '-' +strtrim((end_fill_month), 1)+ '-' +strtrim((end_fill_day), 1)+ ' ' +strtrim((end_fill_hour), 1)+ ':' +strtrim((end_fill_minute), 1)+ ':' +strmid(strtrim((end_fill_second), 1), 0, 4), $
    flight_model: 0, $
    energy: fltarr(1024), $
    spectrum_cps: fltarr(1024), $
    spectrum_cps_accuracy: fltarr(1024), $
    spectrum_cps_precision: fltarr(1024), $
    spectrum_cps_stddev: fltarr(1024), $
    spectrum_total_counts: fltarr(1024), $
    spectrum_total_counts_accuracy: fltarr(1024), $
    spectrum_total_counts_precision: fltarr(1024),$
    integration_time: 0.0, $
    number_spectra: 0L, $
    x123_fast_count: 0.0, $
    x123_slow_count: 0.0, $
    sps_on: 0, $
    sps_sum: 0.0, $
    sps_x: 0.0, $
    sps_y: 0.0, $
    sps_x_hk: 0.0, $
    sps_y_hk: 0.0, $
    longitude: 0.0, $
    latitude: 0.0, $
    altitude: 0.0, $
    spacecraft_in_saa: 0.0, $
    sun_right_ascension: 0.0, $
    sun_declination: 0.0, $
    earth_sun_distance: 0.0, $
    correct_au: 0.0}

  ; minxss-1 xp data structure
  level1_xp = { time: minxsslevel0d[0].time, $
    interval_start_time_jd: x_minute_jd_time_array[0], $
    interval_end_time_jd: x_minute_jd_time_array[1], $
    interval_start_time_human: strtrim((start_fill_year), 1)+ '-' +strtrim((start_fill_month), 1)+ '-' +strtrim((start_fill_day), 1)+ ' ' +strtrim((start_fill_hour), 1)+ ':' +strtrim((start_fill_minute), 1)+ ':' +strmid(strtrim((start_fill_second), 1), 0, 4), $
    interval_end_time_human: strtrim((end_fill_year), 1)+ '-' +strtrim((end_fill_month), 1)+ '-' +strtrim((end_fill_day), 1)+ ' ' +strtrim((end_fill_hour), 1)+ ':' +strtrim((end_fill_minute), 1)+ ':' +strmid(strtrim((end_fill_second), 1), 0, 4), $
    flight_model: 0, $
    signal_fc: 0.0, $
    signal_fc_accuracy: 0.0, $
    signal_fc_precision: 0.0, $
    signal_fc_stddev: 0.0, $
    integration_time: 0.0, $
    ;x123_estimated_xp_fc: 0.0, $
    ;x123_estimated_xp_fc_uncertainty: 0.0, $
    ;fractional_difference_x123_estimated_xp_fc: 0.0, $
    number_xp_samples: 0}


  ; minxss-1 xp dark data structure
  level1_xp_dark = { time: minxsslevel0d[0].time, $
    interval_start_time_jd: x_minute_jd_time_array[0], $
    interval_end_time_jd: x_minute_jd_time_array[1], $
    interval_start_time_human: strtrim((start_fill_year), 1)+ '-' +strtrim((start_fill_month), 1)+ '-' +strtrim((start_fill_day), 1)+ ' ' +strtrim((start_fill_hour), 1)+ ':' +strtrim((start_fill_minute), 1)+ ':' +strmid(strtrim((start_fill_second), 1), 0, 4), $
    interval_end_time_human: strtrim((end_fill_year), 1)+ '-' +strtrim((end_fill_month), 1)+ '-' +strtrim((end_fill_day), 1)+ ' ' +strtrim((end_fill_hour), 1)+ ':' +strtrim((end_fill_minute), 1)+ ':' +strmid(strtrim((end_fill_second), 1), 0, 4), $
    flight_model: 0, $
    signal_fc: 0.0, $
    signal_fc_accuracy: 0.0, $
    signal_fc_precision: 0.0, $
    signal_fc_stddev: 0.0, $
    integration_time: 0.0, $
    ;x123_estimated_xp_fc: 0.0, $
    ;x123_estimated_xp_fc_uncertainty: 0.0, $
    ;fractional_difference_x123_estimated_xp_fc: 0.0, $
    number_xp_samples: 0}

  ; set the initial number of times to initiate the forloop below
  num_L1_fill = 0L
  num_L1_fill_dark = 0L
  num_L1_fill_xp = 0L
  num_xp_fill_dark = 0L

  ; set the initial structure to replicate in the for loop below
  ; x123 science
  start_index_x123_x_minute_jd_time_array_original = {structure:0L}
  start_index_x123_x_minute_jd_time_array = {structure:0L}
  ; x123 dark
  start_index_x123_dark_x_minute_jd_time_array_original = {structure:0L}
  start_index_x123_dark_x_minute_jd_time_array = {structure:0L}
  ; xp science
  start_index_xp_x_minute_jd_time_array_original = {structure:0L}
  start_index_xp_x_minute_jd_time_array = {structure:0L}
  ; xp dark
  start_index_xp_dark_x_minute_jd_time_array_original = {structure:0L}
  start_index_xp_dark_x_minute_jd_time_array = {structure:0L}

  ; find how many pre-set time intervals have the desired MinXSS data to fill in with data later
  for k=0L, n_time_frames_long-2 do begin
    ; loop for the X123 science data
    index_x_minute_average_loop_fill = where((minxsslevel0d[wsci].time.jd ge x_minute_jd_time_array[k]) and (minxsslevel0d[wsci].time.jd le x_minute_jd_time_array[k+1]), n_valid)
    if n_valid gt 0 then begin
      num_L1_fill = num_L1_fill + 1
      start_index_x123_x_minute_jd_time_array_old = start_index_x123_x_minute_jd_time_array
      start_index_x123_x_minute_jd_time_array = replicate(start_index_x123_x_minute_jd_time_array_original, num_L1_fill+1)
      start_index_x123_x_minute_jd_time_array[0:num_L1_fill-1].structure = start_index_x123_x_minute_jd_time_array_old.structure
      start_index_x123_x_minute_jd_time_array[num_L1_fill].structure = k
    endif

    ; xp science data
    index_x_minute_average_loop_fill_xp = where((minxsslevel0d[wsci_xp].time.jd ge x_minute_jd_time_array[k]) and (minxsslevel0d[wsci_xp].time.jd le x_minute_jd_time_array[k+1]) and (((minxsslevel0d[wsci_xp].XPS_DATA_SCI/minxsslevel0d[wsci_xp].sps_xp_integration_time) - (minxsslevel0d[wsci_xp].SPS_DARK_DATA_SCI/minxsslevel0d[wsci_xp].sps_xp_integration_time)) gt 0), n_valid_xp)
    if n_valid_xp gt 0 then begin
      num_L1_fill_xp = num_L1_fill_xp + 1
      start_index_xp_x_minute_jd_time_array_old = start_index_xp_x_minute_jd_time_array
      start_index_xp_x_minute_jd_time_array = replicate(start_index_xp_x_minute_jd_time_array_original, num_L1_fill_xp+1)
      start_index_xp_x_minute_jd_time_array[0:num_L1_fill_xp-1].structure = start_index_xp_x_minute_jd_time_array_old.structure
      start_index_xp_x_minute_jd_time_array[num_L1_fill_xp].structure = k
    endif

    ; x123 dark data
    index_x_minute_average_loop_fill_dark = where((minxsslevel0d[wdark].time.jd ge x_minute_jd_time_array[k]) and (minxsslevel0d[wdark].time.jd le x_minute_jd_time_array[k+1]), n_valid_dark)
    if n_valid_dark gt 0 then begin
      num_L1_fill_dark = num_L1_fill_dark + 1
      start_index_x123_dark_x_minute_jd_time_array_old = start_index_x123_dark_x_minute_jd_time_array
      start_index_x123_dark_x_minute_jd_time_array = replicate(start_index_x123_dark_x_minute_jd_time_array_original, num_L1_fill_dark+1)
      start_index_x123_dark_x_minute_jd_time_array[0:num_L1_fill_dark-1].structure = start_index_x123_dark_x_minute_jd_time_array_old.structure
      start_index_x123_dark_x_minute_jd_time_array[num_L1_fill_dark].structure = k
    endif

    ; xp dark data
    index_x_minute_average_loop_fill_xp_dark = where((minxsslevel0d[wsci_xp_dark].time.jd ge x_minute_jd_time_array[k]) and (minxsslevel0d[wsci_xp_dark].time.jd le x_minute_jd_time_array[k+1]), n_valid_xp_dark)
    if n_valid_xp_dark gt 0 then begin
      num_xp_fill_dark = num_xp_fill_dark + 1
      start_index_xp_dark_x_minute_jd_time_array_old = start_index_xp_dark_x_minute_jd_time_array
      start_index_xp_dark_x_minute_jd_time_array = replicate(start_index_xp_dark_x_minute_jd_time_array_original, num_xp_fill_dark+1)
      start_index_xp_dark_x_minute_jd_time_array[0:num_xp_fill_dark-1].structure = start_index_xp_dark_x_minute_jd_time_array_old.structure
      start_index_xp_dark_x_minute_jd_time_array[num_xp_fill_dark].structure = k
    endif
  endfor

  ; fill in the xp_dark data
  num_xp_fill_dark = num_L1_fill_dark
  start_index_xp_dark_x_minute_jd_time_array = start_index_x123_dark_x_minute_jd_time_array

  ; replicate the structure to the actual number of MinXSS spectra that is valid in the time interval
  minxsslevel1_x123 = replicate(level1_x123, num_L1_fill > 1)
  minxsslevel1_x123_dark = replicate(level1_x123_dark, num_L1_fill_dark > 1)
  minxsslevel1_xp = replicate(level1_xp, num_L1_fill_xp > 1)
  minxsslevel1_xp_dark = replicate(level1_xp_dark, num_xp_fill_dark > 1)

  ; calculate parameters and fill in the structures
  num_L1 = 0L
  num_L1_dark = 0L
  num_L1_xp = 0L
  num_L1_xp_dark = 0L
  num_10percent = long(num_L1_fill/10.)

  ; loop over only the time indices that are known to have minxss data within the x-minute for the current index
  for k=1, num_L1_fill do begin
    ; loop for the X123 science data
    index_x_minute_average_loop = where((minxsslevel0d[wsci].time.jd ge x_minute_jd_time_array[start_index_x123_x_minute_jd_time_array[k].structure]) and (minxsslevel0d[wsci].time.jd le x_minute_jd_time_array[start_index_x123_x_minute_jd_time_array[k].structure + 1]), n_valid)
    IF n_valid EQ 0 THEN CONTINUE

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; start x123 science ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; convert jd back to calendar date for clarity
    caldat, x_minute_jd_time_array[start_index_x123_x_minute_jd_time_array[k].structure], start_valid_month, start_valid_day, start_valid_year, start_valid_hour, start_valid_minute, start_valid_second
    caldat, x_minute_jd_time_array[start_index_x123_x_minute_jd_time_array[k].structure + 1], end_valid_month, end_valid_day, end_valid_year, end_valid_hour, end_valid_minute, end_valid_second

    ; 4. Deadtime correction
    if keyword_set(verbose) then verbose_deadtime=verbose
    x123_counts_deadtime_corrected = minxss_x123_correct_deadtime(float(minxsslevel0d[wsci[index_x_minute_average_loop]].x123_spectrum), minxsslevel0d[wsci[index_x_minute_average_loop]].x123_accum_time, x123_energy_bin_centers_kev=energy_bins_kev, minxss_instrument_structure_data_file=minxss_calibration_file_path, flight_model_number=1, verbose=verbose_deadtime, $ low_energy_limit=low_energy_limit,  $
      deadtime_correction_scale_factor=x123_deadtime_correction_scale_factor_array)
    ; deadtime corrected slow counts
    x123_slow_count_deadtime_corrected = (total(x123_counts_deadtime_corrected, 1, /double, /nan))/(minxsslevel0d[wsci[index_x_minute_average_loop]].x123_accum_time/1000.)

    ; 5.  Calculate the uncertainties
    ; incorporate the SURF relative uncertainty of 10%, to be added in quadrature with the other uncertainties
    ; pre-flight cal uncertainty (SURF) is ~10%
    pre_flight_cal_uncertainty = 0.1

    ; accuracy, calculation from Tom Woods
    x123_cps_mean_count_rate_uncertainty_accuracy = minxss_X123_mean_count_rate_uncertainty(x123_counts_deadtime_corrected, x123_energy_bin_centers_kev=energy_bins_kev, integration_time_array=minxsslevel0d[wsci[index_x_minute_average_loop]].x123_accum_time, fractional_systematic_uncertainty=pre_flight_cal_uncertainty, $ uncertainty_integration_time=uncertatinty_integration_time, uncertainty_fov=uncertainty_fov, use_bin_width=use_bin_width, use_detector_area=use_detector_area, $
      x123_mean_count_rate = x123_cps_mean_count_rate, $
      relative_uncertainty_x123_mean_count_rate = x123_cps_mean_count_rate_relative_uncertainty_accuracy, $
      uncertainty_x123_measured_count_array=x123_measured_count_array_uncertainty, $
      x123_count_rate = x123_cps_count_rate, $
      uncertainty_x123_measured_count_rate_array=x123_cps_count_rate_uncertainty_accuracy, $
      uncertainty_stddev_x123_mean_count_rate=x123_cps_count_rate_stddev, $
      ratio_uncertainty_stddev_x123_mean_count_rate = x123_cps_mean_count_rate_ratio_uncertainty_stddev, $
      X123_Summed_Counts=X123_total_counts, $
      X123_uncertainty_Summed_Counts = X123_total_counts_uncertainty_accuracy, $
      X123_Summed_Integration_time_seconds=X123_total_integration_time)

    x123_cps_mean_count_rate_uncertainty_precision = minxss_X123_mean_count_rate_uncertainty(x123_counts_deadtime_corrected, x123_energy_bin_centers_kev=energy_bins_kev, integration_time_array=minxsslevel0d[wsci[index_x_minute_average_loop]].x123_accum_time, $ fractional_systematic_uncertainty=pre_flight_cal_uncertainty, $ uncertainty_integration_time=uncertatinty_integration_time, uncertainty_fov=uncertainty_fov, use_bin_width=use_bin_width, use_detector_area=use_detector_area, $
      x123_mean_count_rate = x123_cps_mean_count_rate, $
      x123_count_rate = x123_cps_count_rate, $
      uncertainty_x123_measured_count_rate_array=x123_cps_count_rate_uncertainty_precision, $
      X123_uncertainty_Summed_Counts = X123_total_counts_uncertainty_precision)

    ; 6.  Calculate the MinXSS X123 irradiance
    minxss_x123_irradiance_wrapper, x123_cps_mean_count_rate, x123_cps_mean_count_rate_uncertainty_accuracy, x123_irradiance_mean, result=x123_irradiance_structure, fm=fm

    ; 8. Put data into structures
    ; fill the variables in the level1_x123 structure
    correct_1AU = (minxsslevel0d[wsci[index_x_minute_average_loop[0]]].earth_sun_distance)^2.
    minxsslevel1_x123[num_L1].time = minxsslevel0d[wsci[index_x_minute_average_loop[0]]].time
    minxsslevel1_x123[num_L1].interval_start_time_jd = x_minute_jd_time_array[k]
    minxsslevel1_x123[num_L1].interval_end_time_jd = x_minute_jd_time_array[k+1]
    minxsslevel1_x123[num_L1].interval_start_time_human = strtrim((start_valid_year), 1)+ '-' +strtrim((start_valid_month), 1)+ '-' +strtrim((start_valid_day), 1)+ ' ' +strtrim((start_valid_hour), 1)+ ':' +strtrim((start_valid_minute), 1)+ ':' +strmid(strtrim((start_valid_second), 1), 0, 4)
    minxsslevel1_x123[num_L1].interval_end_time_human = strtrim((end_valid_year), 1)+ '-' +strtrim((end_valid_month), 1)+ '-' +strtrim((end_valid_day), 1)+ ' ' +strtrim((end_valid_hour), 1)+ ':' +strtrim((end_valid_minute), 1)+ ':' +strmid(strtrim((end_valid_second), 1), 0, 4)
    minxsslevel1_x123[num_L1].flight_model = minxsslevel0d[wsci[index_x_minute_average_loop[0]]].flight_model
    minxsslevel1_x123[num_L1].irradiance = x123_irradiance_structure.irradiance*correct_1AU
    minxsslevel1_x123[num_L1].irradiance_uncertainty = x123_irradiance_structure.IRRADIANCE_UNCERTAINTY*correct_1AU
    minxsslevel1_x123[num_L1].energy = energy_bins_kev
    minxsslevel1_x123[num_L1].spectrum_cps = x123_cps_mean_count_rate
    minxsslevel1_x123[num_L1].spectrum_cps_accuracy = x123_cps_mean_count_rate_uncertainty_accuracy
    minxsslevel1_x123[num_L1].spectrum_cps_precision = x123_cps_mean_count_rate_uncertainty_precision
    minxsslevel1_x123[num_L1].spectrum_cps_stddev = !VALUES.F_NAN
    minxsslevel1_x123[num_L1].deadtime_correction_factor = x123_deadtime_correction_scale_factor_array[0]
    minxsslevel1_x123[num_L1].spectrum_total_counts = X123_total_counts
    minxsslevel1_x123[num_L1].spectrum_total_counts_accuracy = X123_total_counts_uncertainty_accuracy
    minxsslevel1_x123[num_L1].spectrum_total_counts_precision = X123_total_counts_uncertainty_precision
    minxsslevel1_x123[num_L1].valid_flag = x123_irradiance_structure.valid_flag
    minxsslevel1_x123[num_L1].integration_time = X123_total_integration_time
    minxsslevel1_x123[num_L1].number_spectra = n_valid
    minxsslevel1_x123[num_L1].x123_fast_count = fast_count[wsci[index_x_minute_average_loop[0]]]
    minxsslevel1_x123[num_L1].x123_slow_count = x123_slow_count_deadtime_corrected[0]
    minxsslevel1_x123[num_L1].sps_on = minxsslevel0d[wsci[index_x_minute_average_loop[0]]].switch_sps
    minxsslevel1_x123[num_L1].sps_sum = sps_sum[wsci[index_x_minute_average_loop[0]]]
    minxsslevel1_x123[num_L1].sps_x = sps_x[wsci[index_x_minute_average_loop[0]]]
    minxsslevel1_x123[num_L1].sps_y = sps_y[wsci[index_x_minute_average_loop[0]]]
    minxsslevel1_x123[num_L1].sps_x_hk = (minxsslevel0d[wsci[index_x_minute_average_loop[0]]].sps_x_hk/10000.)*sps_x_factor ; degrees
    minxsslevel1_x123[num_L1].sps_y_hk = (minxsslevel0d[wsci[index_x_minute_average_loop[0]]].sps_y_hk/10000.)*sps_y_factor ; degrees
    minxsslevel1_x123[num_L1].longitude = minxsslevel0d[wsci[index_x_minute_average_loop[0]]].longitude
    minxsslevel1_x123[num_L1].latitude = minxsslevel0d[wsci[index_x_minute_average_loop[0]]].latitude
    minxsslevel1_x123[num_L1].altitude = minxsslevel0d[wsci[index_x_minute_average_loop[0]]].altitude
    minxsslevel1_x123[num_L1].spacecraft_in_saa = minxsslevel0d[wsci[index_x_minute_average_loop[0]]].spacecraft_in_saa
    minxsslevel1_x123[num_L1].sun_right_ascension = minxsslevel0d[wsci[index_x_minute_average_loop[0]]].sun_right_ascension
    minxsslevel1_x123[num_L1].sun_declination = minxsslevel0d[wsci[index_x_minute_average_loop[0]]].sun_declination
    minxsslevel1_x123[num_L1].earth_sun_distance = minxsslevel0d[wsci[index_x_minute_average_loop[0]]].earth_sun_distance
    minxsslevel1_x123[num_L1].correct_au = correct_1AU

    if n_valid gt 1 then begin
      minxsslevel1_x123[num_L1].spectrum_cps_stddev = stddev(x123_cps_count_rate, dimension = 2, /double, /nan)
      minxsslevel1_x123[num_L1].deadtime_correction_factor = mean(x123_deadtime_correction_scale_factor_array, /double, /nan)
      minxsslevel1_x123[num_L1].x123_fast_count = mean(fast_count[wsci[index_x_minute_average_loop]], /double, /nan)
      minxsslevel1_x123[num_L1].x123_slow_count = mean(x123_slow_count_deadtime_corrected, /double, /nan)
      minxsslevel1_x123[num_L1].sps_sum = mean(sps_sum[wsci[index_x_minute_average_loop]], /double, /nan)
      minxsslevel1_x123[num_L1].sps_x = mean(sps_x[wsci[index_x_minute_average_loop]], /double, /nan)
      minxsslevel1_x123[num_L1].sps_y = mean(sps_y[wsci[index_x_minute_average_loop]], /double, /nan)
      minxsslevel1_x123[num_L1].sps_x_hk = mean((minxsslevel0d[wsci[index_x_minute_average_loop]].sps_x_hk/10000.)*sps_x_factor, /double, /nan) ; degrees
      minxsslevel1_x123[num_L1].sps_y_hk = mean((minxsslevel0d[wsci[index_x_minute_average_loop]].sps_y_hk/10000.)*sps_y_factor, /double, /nan) ; degrees
      minxsslevel1_x123[num_L1].longitude = mean(minxsslevel0d[wsci[index_x_minute_average_loop]].longitude, /double, /nan)
      minxsslevel1_x123[num_L1].latitude = mean(minxsslevel0d[wsci[index_x_minute_average_loop]].latitude, /double, /nan)
      minxsslevel1_x123[num_L1].altitude = mean(minxsslevel0d[wsci[index_x_minute_average_loop]].altitude, /double, /nan)
      minxsslevel1_x123[num_L1].sun_right_ascension = mean(minxsslevel0d[wsci[index_x_minute_average_loop]].sun_right_ascension, /double, /nan)
      minxsslevel1_x123[num_L1].sun_declination = mean(minxsslevel0d[wsci[index_x_minute_average_loop]].sun_declination, /double, /nan)
      minxsslevel1_x123[num_L1].earth_sun_distance = mean(minxsslevel0d[wsci[index_x_minute_average_loop]].earth_sun_distance, /double, /nan)
    endif

    ; increment k and num_L1
    if keyword_set(debug) and (k eq 0) then stop, 'DEBUG at first L1 entry...'
    num_L1 += 1
  endfor
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; end x123 science ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; find data within x-minute of current index
  for k=1, num_L1_fill_xp do begin
    index_x_minute_average_loop_xp = where((minxsslevel0d[wsci_xp].time.jd ge x_minute_jd_time_array[start_index_xp_x_minute_jd_time_array[k].structure]) and (minxsslevel0d[wsci_xp].time.jd le x_minute_jd_time_array[start_index_xp_x_minute_jd_time_array[k].structure + 1]) and (((minxsslevel0d[wsci_xp].XPS_DATA_SCI/minxsslevel0d[wsci_xp].sps_xp_integration_time) - (minxsslevel0d[wsci_xp].SPS_DARK_DATA_SCI/minxsslevel0d[wsci_xp].sps_xp_integration_time)) gt 0), n_valid_xp)
    if n_valid_xp EQ 0 then CONTINUE

    ;convert jd back to calendar date for clarity
    caldat, x_minute_jd_time_array[start_index_xp_x_minute_jd_time_array[k].structure], start_valid_month, start_valid_day, start_valid_year, start_valid_hour, start_valid_minute, start_valid_second
    caldat, x_minute_jd_time_array[start_index_xp_x_minute_jd_time_array[k].structure + 1], end_valid_month, end_valid_day, end_valid_year, end_valid_hour, end_valid_minute, end_valid_second

    ; 7. Include background (from the dark diode) subtracted XP data
    ; incorporate the SURF relative uncertainty of 10%, to be added in quadrature with the other uncertainties
    pre_flight_cal_uncertainty = 0.1

    XP_data_Uncertainty_mean_DN_rate_accuracy = minxss_XP_mean_count_rate_uncertainty(minxsslevel0d[wsci_xp[index_x_minute_average_loop_xp]].XPS_DATA_SCI, integration_time_array=minxsslevel0d[wsci_xp[index_x_minute_average_loop_xp]].sps_xp_integration_time, XP_Dark_measured_count_array=minxsslevel0d[wsci_xp[index_x_minute_average_loop_xp]].SPS_DARK_DATA_SCI, dark_integration_time_array=minxsslevel0d[wsci_xp[index_x_minute_average_loop_xp]].sps_xp_integration_time, fractional_systematic_uncertainty=pre_flight_cal_uncertainty, $
        XP_mean_count_rate=XP_data_mean_DN_rate, $
        relative_uncertainty_XP_mean_count_rate=xp_data_relative_Uncertainty_mean_DN_rate, $
        uncertainty_XP_measured_count_array=xp_data_uncertainty_measured_DN_array, $
        XP_count_rate=xp_data_DN_rate, $
        uncertainty_XP_measured_count_rate_array=xp_data_uncertainty_DN_rate_accuracy, $
        background_subtracted_mean_count_rate = xp_data_background_subtracted_mean_DN_rate, $
        uncertainty_background_subtracted_mean_count_rate = xp_data_uncertainty_background_subtracted_mean_DN_rate_accuracy, $
        background_subtracted_count_rate = xp_data_background_subtracted_DN_rate, $
        uncertainty_background_subtracted_count_rate = xp_data_uncertainty_background_subtracted_DN_rate_accuracy, $
        mean_background_subtracted_count_rate = xp_data_mean_background_subtracted_DN_rate, $
        uncertainty_mean_background_subtracted_count_rate = xp_data_uncertainty_mean_background_subtracted_DN_rate_accuracy, $
        Out_XP_mean_Dark_count_rate=xp_data_mean_dark_DN_rate, $
        Out_relative_uncertainty_XP_mean_dark_count_rate = xp_data_relative_Uncertainty_mean_dark_DN_rate, $
        out_uncertainty_XP_measured_dark_count_array = xp_data_uncertainty_measured_dark_DN_array_accuracy, $
        out_dark_count_rate = xp_data_dark_DN_rate, $
        out_uncertainty_XP_measured_dark_count_rate_array=xp_data_uncertainty_dark_DN_rate_accuracy)

    ; Precision
    XP_data_Uncertainty_mean_DN_rate_precision = minxss_XP_mean_count_rate_uncertainty(minxsslevel0d[wsci_xp[index_x_minute_average_loop_xp]].XPS_DATA_SCI, integration_time_array=minxsslevel0d[wsci_xp[index_x_minute_average_loop_xp]].sps_xp_integration_time, XP_Dark_measured_count_array=minxsslevel0d[wsci_xp[index_x_minute_average_loop_xp]].SPS_DARK_DATA_SCI, dark_integration_time_array=minxsslevel0d[wsci_xp[index_x_minute_average_loop_xp]].sps_xp_integration_time, $ fractional_systematic_uncertainty=pre_flight_cal_uncertainty, $
        uncertainty_XP_measured_count_rate_array=xp_data_uncertainty_DN_rate_precision, $
        uncertainty_background_subtracted_mean_count_rate = xp_data_uncertainty_background_subtracted_mean_DN_rate_precision, $
        uncertainty_background_subtracted_count_rate = xp_data_uncertainty_background_subtracted_DN_rate_precision, $
        uncertainty_mean_background_subtracted_count_rate = xp_data_uncertainty_mean_background_subtracted_DN_rate_precision, $
        out_uncertainty_XP_measured_dark_count_array = xp_data_uncertainty_measured_dark_DN_array_precision, $
        out_uncertainty_XP_measured_dark_count_rate_array=xp_data_uncertainty_dark_DN_rate_precision)

    ; Calculate the fA data
    xp_data_mean_background_subtracted_fC_rate = minxss_detector_response.XP_FC_PER_DN*xp_data_mean_background_subtracted_DN_rate
    xp_data_uncertainty_mean_background_subtracted_fC_rate_accuracy = minxss_detector_response.XP_FC_PER_DN*xp_data_uncertainty_mean_background_subtracted_DN_rate_accuracy
    xp_data_uncertainty_mean_background_subtracted_fC_rate_precision = minxss_detector_response.XP_FC_PER_DN*xp_data_uncertainty_mean_background_subtracted_DN_rate_precision
    XP_fc_precision = xp_data_uncertainty_mean_background_subtracted_fC_rate_precision
    XP_fc_accuracy = xp_data_uncertainty_mean_background_subtracted_fC_rate_accuracy

    ; 7. Compare the predicted XP signal from the X123 measurements
    ; Compare x123 to the XP measurements
    ; use a nominal 0.0 energy bin offset
    energy_bins_offset_zero = 0.0
    if keyword_set(verbose) then verbose_xp_signal_from_x123_signal = verbose

    xp_data_x123_mean_photon_flux_photopeak_XP_Signal = minxss_XP_signal_from_X123_signal(energy_bins_kev, energy_bins_offset_zero, x123_cps_mean_count_rate, counts_uncertainty=x123_cps_mean_count_rate_uncertainty_accuracy, minxss_instrument_structure_data_file=minxss_calibration_file_path, /use_detector_area, verbose=verbose_xp_signal_from_x123_signal, $
      output_xp_DN_signal_estimate_be_photoelectron_only_ARRAY=xp_data_mean_DN_signal_estimate_be_photoelectron_only, $
      output_uncertainty_xp_DN_signal_estimate_be_photoelectron_only_ARRAY=xp_data_uncertainty_xp_mean_DN_signal_estimate_be_photoelectron_only, $
      output_xp_fC_signal_estimate_be_photoelectron_only_ARRAY=xp_data_mean_fC_signal_estimate_be_photoelectron_only, $
      output_uncertainty_xp_fC_signal_estimate_be_photoelectron_only_ARRAY=xp_data_uncertainty_mean_xp_fC_signal_estimate_be_photoelectron_only)

    Fractional_Difference_xp_data_mean_DN_signal_estimate_be_photoelectron_only = (xp_data_mean_background_subtracted_DN_rate - xp_data_mean_DN_signal_estimate_be_photoelectron_only)/xp_data_mean_background_subtracted_DN_rate
    Fractional_Difference_xp_data_mean_fC_signal_estimate_be_photoelectron_only = (xp_data_mean_background_subtracted_fC_rate - xp_data_mean_fC_signal_estimate_be_photoelectron_only)/xp_data_mean_background_subtracted_fC_rate

    ; 8. Put data into structures
    ; fill the variables in the level1_xp structure
    minxsslevel1_xp[num_L1_xp].time = minxsslevel0d[wsci_xp[index_x_minute_average_loop_xp[0]]].time
    minxsslevel1_xp[num_L1_xp].interval_start_time_jd = x_minute_jd_time_array[k]
    minxsslevel1_xp[num_L1_xp].interval_end_time_jd = x_minute_jd_time_array[k+1]
    minxsslevel1_xp[num_L1_xp].interval_start_time_human = strtrim((start_valid_year), 1)+ '-' +strtrim((start_valid_month), 1)+ '-' +strtrim((start_valid_day), 1)+ ' ' +strtrim((start_valid_hour), 1)+ ':' +strtrim((start_valid_minute), 1)+ ':' +strmid(strtrim((start_valid_second), 1), 0, 4)
    minxsslevel1_xp[num_L1_xp].interval_end_time_human = strtrim((end_valid_year), 1)+ '-' +strtrim((end_valid_month), 1)+ '-' +strtrim((end_valid_day), 1)+ ' ' +strtrim((end_valid_hour), 1)+ ':' +strtrim((end_valid_minute), 1)+ ':' +strmid(strtrim((end_valid_second), 1), 0, 4)
    minxsslevel1_xp[num_L1_xp].flight_model = minxsslevel0d[wsci_xp[index_x_minute_average_loop_xp[0]]].flight_model
    minxsslevel1_xp[num_L1_xp].signal_fc = xp_data_mean_background_subtracted_fC_rate
    minxsslevel1_xp[num_L1_xp].signal_fc_accuracy = XP_fc_accuracy
    minxsslevel1_xp[num_L1_xp].signal_fc_precision = XP_fc_precision
    minxsslevel1_xp[num_L1_xp].signal_fc_stddev = !VALUES.F_NAN
    minxsslevel1_xp[num_L1_xp].integration_time = minxsslevel0d[wsci_xp[index_x_minute_average_loop_xp[0]]].sps_xp_integration_time
    ;minxsslevel1_xp[num_L1_xp].x123_estimated_xp_fc = xp_data_mean_fC_signal_estimate_be_photoelectron_only
    ;minxsslevel1_xp[num_L1_xp].x123_estimated_xp_fc_uncertainty = xp_data_uncertainty_mean_xp_fC_signal_estimate_be_photoelectron_only
    ;minxsslevel1_xp[num_L1_xp].fractional_difference_x123_estimated_xp_fc = Fractional_Difference_xp_data_mean_fC_signal_estimate_be_photoelectron_only
    minxsslevel1_xp[num_L1_xp].number_xp_samples = n_valid_xp

    if n_valid_xp gt 1 then begin
      minxsslevel1_xp[num_L1_xp].signal_fc_stddev = stddev(xp_data_background_subtracted_DN_rate, /double, /nan)
      minxsslevel1_xp[num_L1_xp].integration_time = total(minxsslevel0d[wsci_xp[index_x_minute_average_loop_xp]].sps_xp_integration_time, /double, /nan)
    endif

    if keyword_set(debug) and (k eq 0) then stop, 'DEBUG at first L1 entry...'
    num_L1_xp += 1
  endfor ; k loop for XP

  ; dark x123 data
  ; loop for the X123 dark data
  ; find data within x-minute of current index
  for k=1, num_L1_fill_dark do begin
    index_x_minute_average_loop_dark = where((minxsslevel0d[wdark].time.jd ge x_minute_jd_time_array[start_index_x123_dark_x_minute_jd_time_array[k].structure]) and (minxsslevel0d[wdark].time.jd le x_minute_jd_time_array[start_index_x123_dark_x_minute_jd_time_array[k].structure+1]), n_valid_dark)
    if n_valid_dark eq 0 then continue

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; start x123 dark ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; convert jd back to calendar date for clarity
    caldat, x_minute_jd_time_array[start_index_x123_dark_x_minute_jd_time_array[k].structure], start_valid_month, start_valid_day, start_valid_year, start_valid_hour, start_valid_minute, start_valid_second
    caldat, x_minute_jd_time_array[start_index_x123_dark_x_minute_jd_time_array[k].structure + 1], end_valid_month, end_valid_day, end_valid_year, end_valid_hour, end_valid_minute, end_valid_second

    ; 5. Calculate the uncertainties
    ; incorporate the SURF relative uncertainty of 10%, to be added in quadrature with the other uncertainties
    ; pre-flight cal uncertainty (SURF) is ~10%
    pre_flight_cal_uncertainty = 0.1
    x123_cps_mean_count_rate_uncertainty_accuracy = minxss_X123_mean_count_rate_uncertainty(float(minxsslevel0d[wdark[index_x_minute_average_loop_dark]].x123_spectrum), x123_energy_bin_centers_kev=energy_bins_kev, integration_time_array=minxsslevel0d[wdark[index_x_minute_average_loop_dark]].x123_accum_time, fractional_systematic_uncertainty=pre_flight_cal_uncertainty, $ uncertainty_integration_time=uncertatinty_integration_time, uncertainty_fov=uncertainty_fov, use_bin_width=use_bin_width, use_detector_area=use_detector_area, $
      x123_mean_count_rate = x123_cps_mean_count_rate, $
      relative_uncertainty_x123_mean_count_rate = x123_cps_mean_count_rate_relative_uncertainty_accuracy, $
      uncertainty_x123_measured_count_array=x123_measured_count_array_uncertainty, $
      x123_count_rate = x123_cps_count_rate, $
      uncertainty_x123_measured_count_rate_array=x123_cps_count_rate_uncertainty_accuracy, $
      uncertainty_stddev_x123_mean_count_rate=x123_cps_count_rate_stddev, $
      ratio_uncertainty_stddev_x123_mean_count_rate = x123_cps_mean_count_rate_ratio_uncertainty_stddev, $
      X123_Summed_Counts=X123_total_counts, $
      X123_uncertainty_Summed_Counts = X123_total_counts_uncertainty_accuracy, $
      X123_Summed_Integration_time_seconds=X123_total_integration_time)

    x123_cps_mean_count_rate_uncertainty_precision = minxss_X123_mean_count_rate_uncertainty(float(minxsslevel0d[wdark[index_x_minute_average_loop_dark]].x123_spectrum), x123_energy_bin_centers_kev=energy_bins_kev, integration_time_array=minxsslevel0d[wdark[index_x_minute_average_loop_dark]].x123_accum_time, $ fractional_systematic_uncertainty=pre_flight_cal_uncertainty, $ uncertainty_integration_time=uncertatinty_integration_time, uncertainty_fov=uncertainty_fov, use_bin_width=use_bin_width, use_detector_area=use_detector_area, $
      x123_mean_count_rate = x123_cps_mean_count_rate, $
      x123_count_rate = x123_cps_count_rate, $
      uncertainty_x123_measured_count_rate_array=x123_cps_count_rate_uncertainty_precision, $
      X123_uncertainty_Summed_Counts = X123_total_counts_uncertainty_precision)

    ; 8. Put data into structures
    ; fill the variables in the level1_x123 structure
    correct_1AU = (minxsslevel0d[wdark[index_x_minute_average_loop_dark[0]]].earth_sun_distance)^2.
    minxsslevel1_x123_dark[num_L1_dark].time = minxsslevel0d[wdark[index_x_minute_average_loop_dark[0]]].time
    minxsslevel1_x123_dark[num_L1_dark].interval_start_time_jd = x_minute_jd_time_array[k]
    minxsslevel1_x123_dark[num_L1_dark].interval_end_time_jd = x_minute_jd_time_array[k+1]
    minxsslevel1_x123_dark[num_L1_dark].interval_start_time_human = strtrim((start_valid_year), 1)+ '-' +strtrim((start_valid_month), 1)+ '-' +strtrim((start_valid_day), 1)+ ' ' +strtrim((start_valid_hour), 1)+ ':' +strtrim((start_valid_minute), 1)+ ':' +strmid(strtrim((start_valid_second), 1), 0, 4)
    minxsslevel1_x123_dark[num_L1_dark].interval_end_time_human = strtrim((end_valid_year), 1)+ '-' +strtrim((end_valid_month), 1)+ '-' +strtrim((end_valid_day), 1)+ ' ' +strtrim((end_valid_hour), 1)+ ':' +strtrim((end_valid_minute), 1)+ ':' +strmid(strtrim((end_valid_second), 1), 0, 4)
    minxsslevel1_x123_dark[num_L1_dark].flight_model = minxsslevel0d[wdark[index_x_minute_average_loop_dark[0]]].flight_model
    minxsslevel1_x123_dark[num_L1_dark].energy = energy_bins_kev
    minxsslevel1_x123_dark[num_L1_dark].spectrum_cps = x123_cps_mean_count_rate
    minxsslevel1_x123_dark[num_L1_dark].spectrum_cps_accuracy = x123_cps_mean_count_rate_uncertainty_accuracy
    minxsslevel1_x123_dark[num_L1_dark].spectrum_cps_precision = x123_cps_mean_count_rate_uncertainty_precision
    minxsslevel1_x123_dark[num_L1_dark].spectrum_cps_stddev = !VALUES.F_NAN
    minxsslevel1_x123_dark[num_L1_dark].spectrum_total_counts = X123_total_counts
    minxsslevel1_x123_dark[num_L1_dark].spectrum_total_counts_accuracy = X123_total_counts_uncertainty_accuracy
    minxsslevel1_x123_dark[num_L1_dark].spectrum_total_counts_precision = X123_total_counts_uncertainty_precision
    minxsslevel1_x123_dark[num_L1_dark].integration_time = X123_total_integration_time
    minxsslevel1_x123_dark[num_L1_dark].number_spectra = n_valid_dark
    minxsslevel1_x123_dark[num_L1_dark].x123_fast_count = fast_count[wdark[index_x_minute_average_loop_dark[0]]]
    minxsslevel1_x123_dark[num_L1_dark].x123_slow_count = slow_count[wdark[index_x_minute_average_loop_dark[0]]]
    minxsslevel1_x123_dark[num_L1_dark].sps_on = minxsslevel0d[wdark[index_x_minute_average_loop_dark[0]]].switch_sps
    minxsslevel1_x123_dark[num_L1_dark].sps_sum = sps_sum[wdark[index_x_minute_average_loop_dark[0]]]
    minxsslevel1_x123_dark[num_L1_dark].sps_x = sps_x[wdark[index_x_minute_average_loop_dark[0]]]
    minxsslevel1_x123_dark[num_L1_dark].sps_y = sps_y[wdark[index_x_minute_average_loop_dark[0]]]
    minxsslevel1_x123_dark[num_L1_dark].sps_x_hk = (minxsslevel0d[wdark[index_x_minute_average_loop_dark[0]]].sps_x_hk/10000.)*sps_x_factor ; degrees
    minxsslevel1_x123_dark[num_L1_dark].sps_y_hk = (minxsslevel0d[wdark[index_x_minute_average_loop_dark[0]]].sps_y_hk/10000.)*sps_y_factor ; degrees
    minxsslevel1_x123_dark[num_L1_dark].longitude = minxsslevel0d[wdark[index_x_minute_average_loop_dark[0]]].longitude
    minxsslevel1_x123_dark[num_L1_dark].latitude = minxsslevel0d[wdark[index_x_minute_average_loop_dark[0]]].latitude
    minxsslevel1_x123_dark[num_L1_dark].altitude = minxsslevel0d[wdark[index_x_minute_average_loop_dark[0]]].altitude
    minxsslevel1_x123_dark[num_L1_dark].spacecraft_in_saa = minxsslevel0d[wdark[index_x_minute_average_loop_dark[0]]].spacecraft_in_saa
    minxsslevel1_x123_dark[num_L1_dark].sun_right_ascension = minxsslevel0d[wdark[index_x_minute_average_loop_dark[0]]].sun_right_ascension
    minxsslevel1_x123_dark[num_L1_dark].sun_declination = minxsslevel0d[wdark[index_x_minute_average_loop_dark[0]]].sun_declination
    minxsslevel1_x123_dark[num_L1_dark].earth_sun_distance = minxsslevel0d[wdark[index_x_minute_average_loop_dark[0]]].earth_sun_distance
    minxsslevel1_x123_dark[num_L1_dark].correct_au = correct_1AU

    if n_valid_dark gt 1 then begin
      minxsslevel1_x123_dark[num_L1_dark].spectrum_cps_stddev = stddev(x123_cps_count_rate, dimension = 2, /double, /nan)
      minxsslevel1_x123_dark[num_L1_dark].x123_fast_count = mean(fast_count[wdark[index_x_minute_average_loop_dark]], /double, /nan)
      minxsslevel1_x123_dark[num_L1_dark].x123_slow_count = mean(slow_count[wdark[index_x_minute_average_loop_dark]], /double, /nan)
      minxsslevel1_x123_dark[num_L1_dark].sps_sum = mean(sps_sum[wdark[index_x_minute_average_loop_dark]], /double, /nan)
      minxsslevel1_x123_dark[num_L1_dark].sps_x = mean(sps_x[wdark[index_x_minute_average_loop_dark]], /double, /nan)
      minxsslevel1_x123_dark[num_L1_dark].sps_y = mean(sps_y[wdark[index_x_minute_average_loop_dark]], /double, /nan)
      minxsslevel1_x123_dark[num_L1_dark].sps_x_hk = mean((minxsslevel0d[wdark[index_x_minute_average_loop_dark]].sps_x_hk/10000.)*sps_x_factor, /double, /nan) ; degrees
      minxsslevel1_x123_dark[num_L1_dark].sps_y_hk = mean((minxsslevel0d[wdark[index_x_minute_average_loop_dark]].sps_y_hk/10000.)*sps_y_factor, /double, /nan) ; degrees
      minxsslevel1_x123_dark[num_L1_dark].longitude = mean(minxsslevel0d[wdark[index_x_minute_average_loop_dark]].longitude, /double, /nan)
      minxsslevel1_x123_dark[num_L1_dark].latitude = mean(minxsslevel0d[wdark[index_x_minute_average_loop_dark]].latitude, /double, /nan)
      minxsslevel1_x123_dark[num_L1_dark].altitude = mean(minxsslevel0d[wdark[index_x_minute_average_loop_dark]].altitude, /double, /nan)
      minxsslevel1_x123_dark[num_L1_dark].sun_right_ascension = mean(minxsslevel0d[wdark[index_x_minute_average_loop_dark]].sun_right_ascension, /double, /nan)
      minxsslevel1_x123_dark[num_L1_dark].sun_declination = mean(minxsslevel0d[wdark[index_x_minute_average_loop_dark]].sun_declination, /double, /nan)
      minxsslevel1_x123_dark[num_L1_dark].earth_sun_distance = mean(minxsslevel0d[wdark[index_x_minute_average_loop_dark]].earth_sun_distance, /double, /nan)
    endif

    ; increment k and num_L1
    if keyword_set(debug) and (k eq 0) then stop, 'DEBUG at first L1 entry...'
    num_L1_dark += 1
  endfor
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; end x123 dark ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; start xp dark ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  for k=1, num_xp_fill_dark-1 do begin
    index_x_minute_average_loop_dark = where((minxsslevel0d[wsci_xp_dark].time.jd ge x_minute_jd_time_array[start_index_x123_dark_x_minute_jd_time_array[k].structure]) and (minxsslevel0d[wsci_xp_dark].time.jd le x_minute_jd_time_array[start_index_x123_dark_x_minute_jd_time_array[k].structure+1]), n_valid_dark)
    good_xp_dark_indices = where((((minxsslevel0d[wsci_xp_dark[index_x_minute_average_loop_dark]].XPS_DATA_SCI/minxsslevel0d[wsci_xp_dark[index_x_minute_average_loop_dark]].sps_xp_integration_time) - (minxsslevel0d[wsci_xp_dark[index_x_minute_average_loop_dark]].SPS_DARK_DATA_SCI/minxsslevel0d[wsci_xp_dark[index_x_minute_average_loop_dark]].sps_xp_integration_time)) gt 0), n_valid_xp_dark)
    good_xp_dark_in_time_indices = index_x_minute_average_loop_dark[good_xp_dark_indices]

    if n_valid_xp_dark EQ 0 then CONTINUE

    ; 5.  Calculate the uncertainties
    ; Include background (from the dark diode) subtracted XP data
    ; incorporate the SURF relative uncertainty of 10%, to be added in quadrature with the other uncertainties
    pre_flight_cal_uncertainty = 0.1
    XP_data_Uncertainty_mean_DN_rate_accuracy = minxss_XP_mean_count_rate_uncertainty(minxsslevel0d[wsci_xp_dark[good_xp_dark_in_time_indices]].XPS_DATA_SCI, integration_time_array=minxsslevel0d[wsci_xp_dark[good_xp_dark_in_time_indices]].sps_xp_integration_time, XP_Dark_measured_count_array=minxsslevel0d[wsci_xp_dark[good_xp_dark_in_time_indices]].SPS_DARK_DATA_SCI, dark_integration_time_array=minxsslevel0d[wsci_xp_dark[good_xp_dark_in_time_indices]].sps_xp_integration_time, fractional_systematic_uncertainty=pre_flight_cal_uncertainty, $
        XP_mean_count_rate=XP_data_mean_DN_rate, $
        relative_uncertainty_XP_mean_count_rate=xp_data_relative_Uncertainty_mean_DN_rate, $
        uncertainty_XP_measured_count_array=xp_data_uncertainty_measured_DN_array, $
        XP_count_rate=xp_data_DN_rate, $
        uncertainty_XP_measured_count_rate_array=xp_data_uncertainty_DN_rate_accuracy, $
        background_subtracted_mean_count_rate = xp_data_background_subtracted_mean_DN_rate, $
        uncertainty_background_subtracted_mean_count_rate = xp_data_uncertainty_background_subtracted_mean_DN_rate_accuracy, $
        background_subtracted_count_rate = xp_data_background_subtracted_DN_rate, $
        uncertainty_background_subtracted_count_rate = xp_data_uncertainty_background_subtracted_DN_rate_accuracy, $
        mean_background_subtracted_count_rate = xp_data_mean_background_subtracted_DN_rate, $
        uncertainty_mean_background_subtracted_count_rate = xp_data_uncertainty_mean_background_subtracted_DN_rate_accuracy, $
        Out_XP_mean_Dark_count_rate=xp_data_mean_dark_DN_rate, $
        Out_relative_uncertainty_XP_mean_dark_count_rate = xp_data_relative_Uncertainty_mean_dark_DN_rate, $
        out_uncertainty_XP_measured_dark_count_array = xp_data_uncertainty_measured_dark_DN_array_accuracy, $
        out_dark_count_rate = xp_data_dark_DN_rate, $
        out_uncertainty_XP_measured_dark_count_rate_array=xp_data_uncertainty_dark_DN_rate_accuracy)

    ; Precision
    XP_data_Uncertainty_mean_DN_rate_precision = minxss_XP_mean_count_rate_uncertainty(minxsslevel0d[wsci_xp_dark].XPS_DATA_SCI, integration_time_array=minxsslevel0d[wsci_xp_dark].sps_xp_integration_time, XP_Dark_measured_count_array=minxsslevel0d[wsci_xp_dark].SPS_DARK_DATA_SCI, dark_integration_time_array=minxsslevel0d[wsci_xp_dark].sps_xp_integration_time, $ fractional_systematic_uncertainty=pre_flight_cal_uncertainty, $
        uncertainty_XP_measured_count_rate_array=xp_data_uncertainty_DN_rate_precision, $
        uncertainty_background_subtracted_mean_count_rate = xp_data_uncertainty_background_subtracted_mean_DN_rate_precision, $
        uncertainty_background_subtracted_count_rate = xp_data_uncertainty_background_subtracted_DN_rate_precision, $
        uncertainty_mean_background_subtracted_count_rate = xp_data_uncertainty_mean_background_subtracted_DN_rate_precision, $
        out_uncertainty_XP_measured_dark_count_array = xp_data_uncertainty_measured_dark_DN_array_precision, $
        out_uncertainty_XP_measured_dark_count_rate_array=xp_data_uncertainty_dark_DN_rate_precision)

    ; Calculate the fA data
    xp_data_mean_background_subtracted_fC_rate = minxss_detector_response.XP_FC_PER_DN*xp_data_mean_background_subtracted_DN_rate
    xp_data_uncertainty_mean_background_subtracted_fC_rate_accuracy = minxss_detector_response.XP_FC_PER_DN*xp_data_uncertainty_mean_background_subtracted_DN_rate_accuracy
    xp_data_uncertainty_mean_background_subtracted_fC_rate_precision = minxss_detector_response.XP_FC_PER_DN*xp_data_uncertainty_mean_background_subtracted_DN_rate_precision
    XP_fc_precision = xp_data_uncertainty_mean_background_subtracted_fC_rate_precision
    XP_fc_accuracy = xp_data_uncertainty_mean_background_subtracted_fC_rate_accuracy
    ; Compare x123 to the XP measurements
    ; use a nominal 0.0 energy bin offset
    energy_bins_offset_zero = 0.0
    if keyword_set(verbose) then verbose_xp_signal_from_x123_signal = verbose

    xp_data_x123_mean_photon_flux_photopeak_XP_Signal = minxss_XP_signal_from_X123_signal(energy_bins_kev, energy_bins_offset_zero, x123_cps_mean_count_rate, counts_uncertainty=x123_cps_mean_count_rate_uncertainty_accuracy, minxss_instrument_structure_data_file=minxss_calibration_file_path, /use_detector_area, verbose=verbose_xp_signal_from_x123_signal, $ ; input_minxss_xp_gain_fC_per_dn=input_minxss_xp_gain_fC_per_dn, $
        output_xp_DN_signal_estimate_be_photoelectron_only_ARRAY=xp_data_mean_DN_signal_estimate_be_photoelectron_only, $
        output_uncertainty_xp_DN_signal_estimate_be_photoelectron_only_ARRAY=xp_data_uncertainty_xp_mean_DN_signal_estimate_be_photoelectron_only, $
        output_xp_fC_signal_estimate_be_photoelectron_only_ARRAY=xp_data_mean_fC_signal_estimate_be_photoelectron_only, $
        output_uncertainty_xp_fC_signal_estimate_be_photoelectron_only_ARRAY=xp_data_uncertainty_mean_xp_fC_signal_estimate_be_photoelectron_only)

    Fractional_Difference_xp_data_mean_DN_signal_estimate_be_photoelectron_only = (xp_data_mean_background_subtracted_DN_rate - xp_data_mean_DN_signal_estimate_be_photoelectron_only)/xp_data_mean_background_subtracted_DN_rate
    Fractional_Difference_xp_data_mean_fC_signal_estimate_be_photoelectron_only = (xp_data_mean_background_subtracted_fC_rate - xp_data_mean_fC_signal_estimate_be_photoelectron_only)/xp_data_mean_background_subtracted_fC_rate

    ; 8. Put data into structures
    ; fill the variables in the level1_xp structure
    minxsslevel1_xp_dark[num_L1_xp_dark].time = minxsslevel0d[wdark[good_xp_dark_in_time_indices[0]]].time
    minxsslevel1_xp_dark[num_L1_xp_dark].interval_start_time_jd = x_minute_jd_time_array[k]
    minxsslevel1_xp_dark[num_L1_xp_dark].interval_end_time_jd = x_minute_jd_time_array[k+1]
    minxsslevel1_xp_dark[num_L1_xp_dark].interval_start_time_human = strtrim((start_valid_year), 1)+ '-' +strtrim((start_valid_month), 1)+ '-' +strtrim((start_valid_day), 1)+ ' ' +strtrim((start_valid_hour), 1)+ ':' +strtrim((start_valid_minute), 1)+ ':' +strmid(strtrim((start_valid_second), 1), 0, 4)
    minxsslevel1_xp_dark[num_L1_xp_dark].interval_end_time_human = strtrim((end_valid_year), 1)+ '-' +strtrim((end_valid_month), 1)+ '-' +strtrim((end_valid_day), 1)+ ' ' +strtrim((end_valid_hour), 1)+ ':' +strtrim((end_valid_minute), 1)+ ':' +strmid(strtrim((end_valid_second), 1), 0, 4)
    minxsslevel1_xp_dark[num_L1_xp_dark].flight_model = minxsslevel0d[wdark[good_xp_dark_in_time_indices[0]]].flight_model
    minxsslevel1_xp_dark[num_L1_xp_dark].signal_fc = xp_data_mean_background_subtracted_fC_rate
    minxsslevel1_xp_dark[num_L1_xp_dark].signal_fc_accuracy = XP_fc_accuracy
    minxsslevel1_xp_dark[num_L1_xp_dark].signal_fc_precision = XP_fc_precision
    minxsslevel1_xp_dark[num_L1_xp_dark].signal_fc_stddev = !VALUES.F_NAN
    minxsslevel1_xp_dark[num_L1_xp_dark].integration_time = minxsslevel0d[wdark[good_xp_dark_in_time_indices[0]]].sps_xp_integration_time
    ;minxsslevel1_xp_dark[num_L1_xp_dark].x123_estimated_xp_fc = xp_data_mean_fC_signal_estimate_be_photoelectron_only
    ;minxsslevel1_xp_dark[num_L1_xp_dark].x123_estimated_xp_fc_uncertainty = xp_data_uncertainty_mean_xp_fC_signal_estimate_be_photoelectron_only
    ;minxsslevel1_xp_dark[num_L1_xp_dark].fractional_difference_x123_estimated_xp_fc = Fractional_Difference_xp_data_mean_fC_signal_estimate_be_photoelectron_only
    minxsslevel1_xp_dark[num_L1_xp_dark].number_xp_samples = n_valid_xp_dark

    if n_valid_xp_dark gt 1 then begin
      minxsslevel1_xp_dark[num_L1_xp_dark].signal_fc_stddev = stddev(xp_data_background_subtracted_DN_rate, /double, /nan)
      minxsslevel1_xp_dark[num_L1_xp_dark].integration_time = total(minxsslevel0d[wdark[good_xp_dark_in_time_indices]].sps_xp_integration_time, /double, /nan)
    endif

    if keyword_set(debug) and (k eq 0) then stop, 'DEBUG at first L1 entry...'
    num_L1_xp_dark += 1
  endfor
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; end xp dark ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; truncate down to the elements used
  minxsslevel1_x123 = minxsslevel1_x123[0:num_L1-1]
  minxsslevel1_xp = minxsslevel1_xp[0:num_L1_xp-1]
  minxsslevel1_x123_dark = minxsslevel1_x123_dark[0:num_L1_dark-1]
  minxsslevel1_xp_dark = minxsslevel1_xp_dark[0:num_L1_xp_dark-1]

  x_minute_average_string_name_digits = long(Alog10(x_minute_average) + 1)
  x_minute_average_string = strmid(strtrim(x_minute_average, 1), 0, x_minute_average_string_name_digits)

  ; create the file name extension that changes with the minute average chossen as a variable
  x_minute_average_string_name_digits = long(Alog10(x_minute_average) + 1)
  x_minute_average_string = strmid(strtrim(x_minute_average, 1), 0, x_minute_average_string_name_digits)

  ;
  ;	calculate Solar Zenith Angle and Tangent Ray Height  (new for June 2022, T. Woods)
  ;
  time_yd = double(minxsslevel1_x123.time.YYYYDOY) + minxsslevel1_x123.time.YYYYDOY/(24.D0*3600.D0)
  solar_zenith_altitude, time_yd , minxsslevel1_x123.longitude, $
				minxsslevel1_x123.latitude, minxsslevel1_x123.altitude, sza, trh
  minxsslevel1_x123.solar_zenith_angle = sza
  minxsslevel1_x123.tangent_ray_height = trh

  ; define the OUTPUT File Name
  outfile = 'minxss' + fm_str + '_l1_' + x_minute_average_string + '_minute' + '_mission_length_v' + version + '.sav'

  ; x123 information structure
  minxsslevel1_x123_meta = { $
    Title: 'MinXSS Level 1 Data Product, ' + x_minute_average_string + '-min averages', $
    Source: 'MinXSS SOC at LASP / CU', $
    Mission: 'MinXSS-'+fm_str, $
    Data_product_type: 'MinXSS Level 1', $
    VERSION: version, $
    Calibration_version: cal_version, $
    Description: 'Calibrated MinXSS X123 science data averaged over a minute and corrected to 1-AU', $
    History: [ '2016/07/30: Tom Woods: Updated with meta-data, latest Level 0D, and 1-AU correction', $
    '2016/07/25: Tom Woods: Original Level 1 code for first version of Level 0D', '2017/06/23: Chris Moore: added first-order deadtime correction, x minute averaging, XP data'], $
    Filename: outfile, $
    Date_generated: systime(), $
    TIME_struct: 'Time structure for different date/time formats', $
    TIME_struct_ISO: 'Time in ISO text format', $
    TIME_struct_HUMAN: 'Time in Human-readable text format', $
    TIME_struct_YYYYMMDD: 'Time in Year-Month-Day long integer format', $
    TIME_struct_YYYYDOY: 'Time in Year Day-Of-Year (DOY) long integer format', $
    TIME_struct_HHMMSS: 'Time in Hour-Minute-Second text format', $
    TIME_struct_SOD: 'Time in Seconds of Day (SOD) long integer format', $
    TIME_struct_FOD: 'Time in Fraction of Day (FOD) double format', $
    TIME_struct_JD: 'Time in Julian Date double format', $
    TIME_struct_spacecraftgpsformat: 'Time recorded by spacecraft in GPS Seconds double format', $
    INTERVAL_START_TIME_JD: 'Start Time of the Interval in which the data is averaged in Julian Date double format', $
    INTERVAL_END_TIME_JD: 'End Time of the Interval in which the data is averaged in Julian Date double format', $
    INTERVAL_START_TIME_HUMAN: 'Start Time of the Interval in which the data is averaged in Human format - Calendar Date', $
    INTERVAL_END_TIME_HUMAN: 'End Time of the Interval in which the data is averaged in Human format - Calendar Date', $
    FLIGHT_MODEL: 'MinXSS Flight Model integer (1 or 2)', $
    IRRADIANCE: 'X123 Irradiance in units of photons/sec/cm^2/keV, float array[1024]', $
    IRRADIANCE_UNCERTAINTY: 'X123 Irradiance uncertainty, float array[1024]', $
    ENERGY: 'X123 Energy bins in units of keV, float array[1024]', $
    SPECTRUM_CPS: 'X123 Deadtime corrected spectrum in units of counts per second (cps), float array[1024]', $
    SPECTRUM_CPS_ACCURACY: 'X123 Deadtime corrected spectrum uncertainty including the 10% SURF accuracy (cps), float array[1024]', $
    SPECTRUM_CPS_PRECISION: 'X123 Deadtime corrected spectrum uncertainty soley incluting the instrument measurement precision (cps), float array[1024]', $
    SPECTRUM_CPS_STDDEV: 'X123 Deadtime corrected spectrum standard deviation of the ' + x_minute_average_string +'-minute average, float array[1024]', $
    DEADTIME_CORRECTION_FACTOR: 'X123 first order deadtime correction factor, double', $
    VALID_FLAG: 'X123 Valid Flag for Irradiance conversion (1=TRUE, 0=FALSE), float array[1024]', $
    SPECTRUM_TOTAL_COUNTS: 'X123 Deadtime corrected spectrum in units of counts per second (cps), float array[1024]', $
    SPECTRUM_TOTAL_COUNTS_ACCURACY: 'X123 Deadtime corrected spectrum uncertainty including the 10% SURF accuracy (total spectral counts over the entire time frame), float array[1024]', $
    SPECTRUM_TOTAL_COUNTS_PRECISION: 'X123 Deadtime corrected spectrum uncertainty soley incluting the instrument measurement precision (total spectral counts over the entire time frame), float array[1024]', $
    INTEGRATION_TIME: 'X123 Integration Time accumulated over the ' + x_minute_average_string +'-minute average', $
    NUMBER_SPECTRA: 'X123 Number of Spectra in the ' + x_minute_average_string +'-minute average (1-6 possible)', $
    X123_FAST_COUNT: 'X123 Fast Counter value', $
    X123_SLOW_COUNT: 'X123 Slow Counter value: spectral integration of counts over 1024 bins', $
    SPS_ON: 'SPS power flag (1=ON, 0=OFF)', $
    SPS_SUM: 'SPS signal in units of fC, normally about 2E6 fC when in sunlight', $
    SPS_X: 'SPS X-axis offset from the sun center (NaN if SPS is not in the sun)', $
    SPS_Y: 'SPS Y-axis offset from the sun center (NaN if SPS is not in the sun)', $
    SPS_X_HK: 'SPS X-axis offset from the sun center (NaN if SPS is not in the sun)', $
    SPS_Y_HK: 'SPS Y-axis offset from the sun center (NaN if SPS is not in the sun)', $
    LONGITUDE: 'Earth Longitude for this measurement in units of degrees', $
    LATITUDE : 'Earth Latitude for this measurement in units of degrees', $
    ALTITUDE : 'Earth Altitude for this measurement in units of km from Earth center', $
    SPACECRAFT_IN_SAA: 'South Atlantic Anomaly (SAA) Flag (1=In_SAA, 0=Out_of_SAA)', $
    SUN_RIGHT_ASCENSION: 'Sun Right Ascension from orbit location', $
    SUN_DECLINATION: 'Sun Declination from orbit location', $
    SOLAR_ZENITH_ANGLE: 'Solar Zenith Angle from orbit location', $
    TANGENT_RAY_HEIGHT: 'Tangent Ray Height in km in Earth atmosphere', $
    EARTH_SUN_DISTANCE: 'Earth-Sun Distance in units of AU (irradiance is corrected to 1AU)', $
    CORRECT_AU: 'Earth-Sun Distance correction factor' $
  }

  ; xp information structure
  minxsslevel1_xp_meta = { $
    Title: 'MinXSS Level 1 Data Product, ' + x_minute_average_string + '-min  averages corrected', $
    Source: 'MinXSS SOC at LASP / CU', $
    Mission: 'MinXSS-'+fm_str, $
    Data_product_type: 'MinXSS Level 1', $
    VERSION: version, $
    Calibration_version: cal_version, $
    Description: 'Calibrated MinXSS X123 science data averaged over a minute and corrected to 1-AU', $
    History: [ '2016/07/30: Tom Woods: Updated with meta-data, latest Level 0D, and 1-AU correction', $
    '2016/07/25: Tom Woods: Original Level 1 code for first version of Level 0D', '2017/06/23: Chris Moore: added first-order deadtime correction, x minute averaging, XP data'], $
    Filename: outfile, $
    Date_generated: systime(), $
    TIME_struct: 'Time structure for different date/time formats', $
    TIME_struct_ISO: 'Time in ISO text format', $
    TIME_struct_HUMAN: 'Time in Human-readable text format', $
    TIME_struct_YYYYMMDD: 'Time in Year-Month-Day long integer format', $
    TIME_struct_YYYYDOY: 'Time in Year Day-Of-Year (DOY) long integer format', $
    TIME_struct_HHMMSS: 'Time in Hour-Minute-Second text format', $
    TIME_struct_SOD: 'Time in Seconds of Day (SOD) long integer format', $
    TIME_struct_FOD: 'Time in Fraction of Day (FOD) double format', $
    TIME_struct_JD: 'Time in Julian Date double format', $
    TIME_struct_spacecraftgpsformat: 'Time recorded by spacecraft in GPS Seconds double format', $
    INTERVAL_START_TIME_JD: 'Start Time of the Interval in which the data is averaged in Julian Date double format', $
    INTERVAL_END_TIME_JD: 'End Time of the Interval in which the data is averaged in Julian Date double format', $
    INTERVAL_START_TIME_HUMAN: 'Start Time of the Interval in which the data is averaged in Human format - Calendar Date', $
    INTERVAL_END_TIME_HUMAN: 'End Time of the Interval in which the data is averaged in Human format - Calendar Date', $
    FLIGHT_MODEL: 'MinXSS Flight Model integer (1 or 2)', $
    signal_fc: 'XP background subtracted (dark diode) signal in units of femtocoulombs per second (fc/s -> fA), float array[1024]', $
    signal_fc_accuracy: 'XP signal uncertainty including the 10% SURF accuracy (cps), float array[1024]', $
    signal_fc_precision: 'XP signal uncertainty soley incluting the instrument measurement precision (cps), float array[1024]', $
    signal_fc_STDDEV: 'XP signal standard deviation of the ' + x_minute_average_string +'-minute average, float array[1024]', $
    INTEGRATION_TIME: 'X123 Integration Time accumulated over the ' + x_minute_average_string +'-minute average', $
    ;XP_FC_X123_ESTIMATED: 'XP signal estimated from the measured X123 spectra in units of femtocoulombs per second (fc/s -> fA), double array', $
    ;XP_FC_X123_ESTIMATED_UNCERTAINTY: 'XP signal uncertainty of the estimated XP signal from the measured X123 spectra, double array', $
    ;FRACTIONAL_DIFFERENCE_XP_FC_X123_ESTIMATED: 'Fractional difference between the actual measured XP signal and the estimated XP signal from the measured X123 spectra, double array', $
    NUMBER_XP_SAMPLES: 'XP number of samples' $
  }



  ; 9. Save the Level 1 results (mission-length file) data into an IDL .sav file, need to make .fits files also
  ;
  ; create the file name extension that changes with the minute average chossen as a variable
  outdir = fmdir + 'level1' + path_sep()

  if keyword_set(verbose) then print, 'Saving Level 1 save set in ', outdir+outfile
  save, minxsslevel1_x123, minxsslevel1_x123_meta, minxsslevel1_x123_dark, $
        minxsslevel1_xp, minxsslevel1_xp_meta, minxsslevel1_xp_dark, $
        file=outdir+outfile

  if keyword_set(verbose) then print, 'END of minxss_make_level1 at ', systime()

  if keyword_set(debug) then stop, 'DEBUG at end of minxss_make_level1.pro ...'


  RETURN
END
