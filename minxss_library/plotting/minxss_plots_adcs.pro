;+
; NAME:
;   minxss_plots_adcs.pro
;
; PURPOSE:
;   Plot trends of adcs telemetry (tlm) data and merge into single PDF file.
;   User can pass MinXSS adcs packets or specify date/time range for the plots.
;   This is intended for adcs packets but it works for any MinXSS structure.
;   This will not plot tags that are arrays.
;
; CATEGORY:
;   Useful for trend plots with MinXSS Level 0B and Level 0C data.
;
; CALLING SEQUENCE:
;   minxss_trend_adcs, packet, timeRange=timeRange, items=items, pdf=pdf, level=level, layout=layout, /verbose
;
; INPUTS:
;   Either packet or timeRange. Must specify one or the other. See optional inputs below
;   
; OPTIONAL INPUTS:  
;   packet [structure]:       For passing in standard MinXSS packet structures as defined by minxss_read_packets
;   timeRange [dblarr]:       To specify date/time range for the plot in format yyyydoy.fod (fraction of day) e.g. 2015083.43482d. 
;                             Note that IF a long fraction of day is specified, it's important to include the d to make it a double.  
;                             If timeRange is one number, THEN it specifies a date and packet is ignored
;                             and it searches for Level 0 data files
;                             If timeRange is two numbers, THEN it specifies a time range and either uses packet
;                             or it searches for Level 0  data files IF packet is not provided
;   items [intarr or strarr]: Input array to limit which tags are plotted (either tag number or tag name)
;   tlmType [string]:         The type of data to plot e.g., 'ADCS', 'SCI', or other packetname. Default is HK.     
;   level [string]:           To specify 'B' or 'C' for Level 0B or Level 0C (default) data. 
;   layout [intarr]:          To specify number of plots per page = [num_columns, num_rows] 
;
; KEYWORD PARAMETERS:
;   PDF:           Set to save a PDF and don't show on screen. 
;                  If this keyword is not set, THEN the program just displays the plots interactively to the user.
;   VERBOSE:       Set to print progress messages. 
;   NO_TIME_LIMIT: Set to prevent limiting data to the range of time given by timeRange (default is 'NO', to process data for the entire day)
;   
; OUTPUTS:
;   Plots to screen or PDF
;   
; OPTIONAL OUTPUTS: 
;   If PDF keyword is set, saves a multi-page PDF file with all plots
;
; ISSUES:
;   TODO: Need to actually update this code to plot adcs data. 
;
; PROCEDURE:
;   1. Check validity of input
;   2. Find (read) the data IF necessary
;   3. Make plots
;
; MODIFICATION HISTORY:
;   2015/08/18: James Paul Mason: Copied from minxss_plots_trends and edited for adcs.
;   2015/10/23: James Paul Mason: Refactored minxss_processing -> minxss_data and changed affected code to be consistent
;+
PRO minxss_plots_adcs, packet, timeRange = timeRange, items = items, tlmType = tlmType, level = level, layout = layout, $
                        PDF = PDF, VERBOSE = VERBOSE, NO_TIME_LIMIT = NO_TIME_LIMIT

;
; 1. Check validity of input
;
IF timeRange NE !NULL THEN BEGIN
  ; Make doubles for time1, time2
  time1 = double(timeRange[0])
  IF n_elements(timeRange) EQ 2 THEN time2 = double(timeRange[1])
  
  ; Determine if using normal date formatting (e.g., 20150626 instead of DOY) and convert to DOY
  IF strlen(JPMPrintNumber(timeRange, /NO_DECIMALS)) GT 7 THEN BEGIN
    yearDoy1 = JPMDate2DOY(time1)
    IF yearDoy1.doy LT 100 THEN doyString = '0' + strtrim(yearDoy1.doy, 2) ELSE doyString = strtrim(yearDoy1.doy, 2)
    timeRange[0] = long(strtrim(yearDoy1.year, 2) + doyString)
    IF n_elements(timeRange) EQ 2 THEN BEGIN
      yearDoy2 = JPMDate2DOY(time2)
      IF yearDoy2.doy LT 100 THEN doyString = '0' + strtrim(yearDoy2.doy, 2) ELSE doyString = strtrim(yearDoy2.doy, 2)
      timeRange[1] = long(strtrim(yearDoy2.year, 2) + doyString)
    ENDIF
  ENDIF
ENDIF 
IF n_params() GT 0 THEN BEGIN
   ; packet provided by user
  IF keyword_set(timeRange) AND (n_elements(timeRange) EQ 1) THEN BEGIN
    ; ignore packet input if timeRange is single date
    readFiles = 1
    time1 = timeRange[0]
    time2 = timeRange[0]+1L
  ENDIF ELSE begin
    readFiles = 0
  ENDELSE
ENDIF ELSE IF keyword_set(timeRange) THEN BEGIN
  ; get data based on time in timeRange
  readFiles = 1
  IF n_elements(timeRange) EQ 1 THEN BEGIN
    time1 = timeRange[0]
    time2 = timeRange[0]+1L
  ENDIF ELSE begin
    time1 = timeRange[0]
    time2 = timeRange[1]
  ENDELSE
ENDIF ELSE begin
  ; no data or time inputs were provided so need to exit
  print, 'USAGE: minxss_plots_adcs, packet, timeRange=timeRange, items=items, tlmType = tlmType, level=level, layout=layout, /PDF, /VERBOSE, /NO_TIME_LIMIT'
  return
ENDELSE

;
; 2. Find (read) the data if necessary
;
IF (readFiles NE 0) THEN BEGIN
  ; FIXME:  default choice is L0B for now but will want to change it to be L0C for flight
  IF keyword_set(level) THEN BEGIN
    level_str = strlowcase(strmid(level,0,1))
  ENDIF ELSE level_str = 'b'
  IF level_str NE 'b' OR level_str NE 'c' THEN level_str = 'b'

  ;  Define time_day_str based on time1 value expected to be in YYYYDOY format
  time_date = long(time1)
  time_year = long(time_date / 1000.)
  time_doy = time_date mod 1000L
  time_date_str = strtrim(time_year,2) + '_'
  doy_str = strtrim(time_doy,2)
  WHILE strlen(doy_str) LT 3 DO doy_str = '0' + doy_str
  time_date_str += doy_str

  data_dir = getenv('minxss_data') + '/level0' + level_str + '/'
  data_file = 'minxss_l0' + level_str + '_' + time_date_str + '.sav'

   ; see if file exists before continuing
   full_filename = file_search( data_dir + data_file, count=fcount )
   IF (fcount GT 0) THEN BEGIN
     IF keyword_set(verbose) THEN print, 'Restoring data from ', data_file
     restore, data_dir + data_file
     packet = temporary(adcs4)  ;  use the HK packet
     pdf_type = 'adcs'
   ENDIF ELSE begin
     print, 'ERROR: minxss_trend_plots can not find file = ', data_file
     return
   ENDELSE
ENDIF

;
; make time array in hours using the packet.TIME variable
;
packet_time_yd = jd2yd(gps2jd(packet.time))
IF (readFiles EQ 0) THEN BEGIN
  IF keyword_set(timeRange) AND (n_elements(timeRange) GT 1) THEN BEGIN
     time1 = timeRange[0]
     time2 = timeRange[1]
  ENDIF ELSE begin
    time1 = min(packet_time_yd)
    time2 = max(packet_time_yd)
  ENDELSE
  ;  make time_date_str based on time1 value
  time_date = long(time1)
  time_year = long(time_date / 1000.)
  time_doy = time_date mod 1000L
  time_date_str = strtrim(time_year,2) + '_'
  doy_str = strtrim(time_doy,2)
  WHILE strlen(doy_str) LT 3 DO doy_str = '0' + doy_str
  time_date_str += doy_str
ENDIF

;
; exclude data based on time1-time2 range if don't have /NO_TIME_LIMIT
; and make time in hours for plotting
;
IF ~keyword_set(NO_TIME_LIMIT) THEN BEGIN
  wgood = where( packet_time_yd ge time1 AND packet_time_yd le time2, numgood )
  IF (numgood LT 2) THEN BEGIN
    print, 'ERROR: minxss_trend_plots needs valid data in the time range of ' + strtrim(time1,2) + ' - ' + strtrim(time2,2)
    IF keyword_set(verbose) THEN stop, 'DEBUG ...'
    return
  ENDIF
ENDIF ELSE BEGIN
  numgood = n_elements(packet_time_yd)
  wgood = indgen(numgood, /long)
ENDELSE

yd_base = long(time_year * 1000L + time_doy)
pdata = packet[wgood]
ptime = (packet_time_yd[wgood] - yd_base)*24.  ; convert to hours since time1 YD
;
; 3. Make plots
;
; Define indices into HK packet structure for each page AND THEN loop to make plots for each page
; Indices exclude APID, SEQ_FLAGS, SEQ_COUNT, DATA_LENGTH, AND TIME (first 5)
; All indices are used unless items array is provided.
; Layout is portrait page at 150 dpi AND assumes 2 x 3 plots per page unless /layout is given
;
num_col = 2L
num_row = 3L
IF keyword_set(layout) AND (n_elements(layout) ge 2) THEN BEGIN
  num_col = long(layout[0])
  num_row = long(layout[1])
ENDIF
num_plots_per_page = num_col * num_row

;  get structure tag names
plot_names = tag_names( pdata[0] )
plot_num = n_tags( pdata[0] )

;  get indices for the plots
num_exclude = 5
indices = indgen(plot_num-num_exclude) + num_exclude
IF keyword_set(items) THEN BEGIN
  ; sort items names into indices into plot_names OR ELSE just use items numbers as the indices
  items_type = size(items,/type)
  IF (items_type EQ 7) THEN BEGIN
    ; string array
    indices = lonarr(n_elements(items)) - 1L  ; -1L means invalid match
    FOR k=0L,n_elements(items)-1 DO BEGIN
      FOR i=0L,plot_num-1 DO BEGIN
        IF (strcmp(plot_names[i], items[k], /fold_case) EQ 1) THEN BEGIN
          indices[k] = i
          break  ; get out of i loop as found match
        ENDIF
      ENDFOR
    ENDFOR
    wgd = where( (indices ge num_exclude) AND (indices LT plot_num), numgd )
    IF (numgd ge 1) THEN BEGIN
      indices = indices[wgd]
    ENDIF ELSE begin
      print, 'ERROR: minxss_trend_plots needs valid Tag strings in items'
      return
    ENDELSE
  ENDIF ELSE IF (items_type ge 1) AND (items_type le 5) THEN BEGIN
    ; number array
    indices = (long(items) > num_exclude) < (plot_num-1)
  ENDIF ELSE begin
    print, 'ERROR: minxss_trend_plots ITEMS needs to be array of numbers OR strings'
    IF keyword_set(verbose) THEN stop, 'DEBUG ...'
    return
  ENDELSE
ENDIF

;  figure out how many pages to make
num_items = n_elements(indices)
page_count = num_items / num_plots_per_page
IF (page_count * num_plots_per_page) NE num_items THEN page_count += 1
ans = ' '

IF keyword_set(verbose) THEN BEGIN
  print, 'minxss_trend_plots:  ' + strtrim(num_items,2) + ' items will be plotted onto ' + $
      strtrim(page_count,2) + ' pages.'
ENDIF

;  if /PDF is given, then prepare for PDF file to be made
IF keyword_set(pdf) THEN BEGIN
  IF pdf_type EQ !NULL AND tlmType NE !NULL THEN pdf_type = strlowcase(string(tlmType))
  IF (pdf_type NE 'hk') AND (pdf_type NE 'adcs') AND $
     (pdf_type NE 'sci') THEN pdf_type = 'other'
  pdf_dir = getenv('minxss_data') + '/trends/' + pdf_type + '/'
  yyyymmdd = yd2ymd(time1)
  mm = fix(yyyymmdd(1))
  IF mm LT 9 THEN mm = '0' + strtrim(mm, 2) ELSE mm = strtrim(mm, 2)
  dd = fix(yyyymmdd(2))
  IF dd LT 9 THEN dd = '0' + strtrim(dd, 2) ELSE dd = strtrim(dd, 2)
  pdf_file = 'minxss_' + pdf_type + '_' + time_date_str + '_' + mm + dd + '.pdf'
  ; IF keyword_set(verbose) THEN $
    print, 'minxss_trend_plots:  PDF file = ' + pdf_dir + pdf_file
ENDIF

;
; now make the pages of plots
; Use the IDL plot() function with the /layout option AND .SAVE method IF making PDF file
;
title2 = time_date_str
title1 = 'Page '
IF (num_col GT 1) THEN xtitle='UTC [Hour]' ELSE xtitle = 'Hour of ' + time_date_str
xrange = [min(ptime), max(ptime)]
xdim = num_col * 300L
ydim = num_row * 250L
IF num_plots_per_page LT 2 THEN BEGIN
  xdim *= 2L
  ydim *= 2L
ENDIF

; Prepare to keep plot hidden from screen IF PDF is specified
IF keyword_set(PDF) THEN BUFFER = 1 ELSE BUFFER = 0

plotobj = objarr(num_plots_per_page)
plotobj[0] = plot( indgen(10), indgen(10), DIMENSION = [xdim,ydim], /CURRENT, BUFFER=BUFFER, CLIP = 0, FONT_SIZE = 8)  ; dummy plot so window will be erased

FOR k=0L,page_count-1 DO BEGIN
  FOR i=0L,num_plots_per_page-1 DO BEGIN
    pnum = k * num_plots_per_page + i
    IF (pnum LT num_items) THEN BEGIN
      IF (i EQ 0) AND (plotobj[0] NE !NULL) THEN BEGIN
          ; erase the current window
          IF (k NE 0) AND (NOT keyword_set(pdf)) THEN read, 'Ready for next plot ? ', ans
           w = plotobj[0].window
          w.Erase
      ENDIF
      temp_data = pdata.(indices[pnum])
      IF (size(temp_data,/n_dimension) GT 1) THEN BEGIN
        ; compress 2-D data array into total of second dimension
        temp_data = temporary( total(temp_data,2) )
        extra_str = 'Total '
      ENDIF ELSE extra_str = ''
      yrange = [min(temp_data), max(temp_data)]
      mtitle=''
      IF (num_col GT 1) AND (i EQ 1) THEN mtitle=title2
      IF (page_count GT 1) AND (i EQ 0) THEN mtitle=title1 + strtrim(k+1,2)
      plotobj[i] = plot(ptime, temp_data, TITLE = mtitle, /CURRENT, LAYOUT = [num_col, num_row, i+1], MARGIN = [0.2, 0.15, 0.05, 0.1], CLIP = 0, $
                        XRANGE = xrange, XTITLE = xtitle, $
                        YRANGE = yrange, YTITLE = extra_str + plot_names[indices[pnum]])
      ax = plotobj[i].axes
      FOR axisLoopIndex = 0, 3 DO BEGIN 
        ax[axisLoopIndex].CLIP = 0
        ax[axisLoopIndex].tickfont_size = 7
        ax[1].tickformat = '(g10.3)'
      ENDFOR
      ;IF k EQ 2 AND i EQ 2 THEN STOP
    ENDIF
  ENDFOR
  ;
  ; write this page of plots to PDF file
  ;
  IF keyword_set(pdf) THEN BEGIN
     IF k LT (page_count-1) THEN plotobj[0].Save, pdf_dir + pdf_file, RESOLUTION = 150, /APPEND $
     ELSE                        plotobj[0].Save, pdf_dir + pdf_file, RESOLUTION = 150, /APPEND, /CLOSE
  ENDIF
ENDFOR

IF keyword_set(verbose) THEN BEGIN
  print, 'minxss_trend_plots: completed all of the plots'
  ; stop, 'DEBUG the data used in the plots...'
ENDIF

return
END
