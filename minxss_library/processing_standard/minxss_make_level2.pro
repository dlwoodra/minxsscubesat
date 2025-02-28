;+
; NAME:
;   minxss_make_level2.pro
;
; PURPOSE:
;   Read Level 1 data product and make sub-day average data structure to produce Level 2.
;
; INPUTS:
;   None required
;
; OPTIONAL INPUTS:
;   fm [integer]: Flight Model number 1 or 2 (default is 1)
;   version [string]: Set this to specify a particular level 1 file to restore for filtering.
;                     Defaults to '' (nothing), which is intended for situations where you've
;                     just processed level 1 but didn't specify `version` in your call to minxss_make_level1.
;
; OPTIONAL INPUTS:
;   None
;
; KEYWORD PARAMETERS:
;   VERBOSE: Set this to print processing messages
;
; OUTPUTS:
;   None
;
; OPTIONAL OUTPUTS
;   None
;
; COMMON BLOCKS:
;   None
;
; RESTRICTIONS:
;   Requires minxss_find_files.pro
;   Requires minxss_filename_parts.pro
;   Requires minxss_average_packets.pro
;   Uses the library routines for converting time (GPS seconds, Julian date, etc.)
;
; PROCEDURE:
;   1. Call minxss_make_level_xminute for each time average desired (1 minute, 1 hour)
;   2. Move the files it generates to the Level 2 folder
;+
PRO minxss_make_level2, fm=fm, version=version, $
                        VERBOSE=VERBOSE

; Defaults and validity checks - fm
IF fm EQ !NULL THEN fm = 1
if (fm gt 2) or (fm lt 1) then begin
  message, /INFO, JPMsystime() + "ERROR: need a valid 'fm' value. FM can be 1 or 2."
  return
endif
fm_str = strtrim(fm,2)

IF version EQ !NULL THEN version = '3.2.0'
IF ~isA(version, 'string') THEN BEGIN
  message, /INFO, JPMsystime() + " ERROR: version input must be a string"
  return
ENDIF

minxss_make_x123_average, 1L, fm=fm, version=version, VERBOSE=VERBOSE
minxss_make_x123_average, 60L, fm=fm, version=version, VERBOSE=VERBOSE

message, /INFO, JPMsystime() + " All done!"
END
