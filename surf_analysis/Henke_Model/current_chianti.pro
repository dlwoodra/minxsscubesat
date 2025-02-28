;
;	predict current for a diode
;
;	pass in wavelength (w) and sensivity (s) for diode
;		can be calibrated values or predicted values
;		(sensitivity is electrons per photon)
;
;	sigout = Solar Max signal output
;
;	TNW   9/6/93
;
;	added serr input for sensitivity error (in percentage)
;
;	same as current.pro BUT uses ch_ss_sp_dem_all.sav to get solar min and max CHIANTI spectra 
;
pro current_chianti, w, s, serr, wout, sigout, nolabel=nolabel, stopit=stopit, $
	shortwave=shortwave, xrange=xrange

if n_params(0) lt 2 then begin
	print, 'Usage:  current_chianti, w, s, [/nolabel]'
	diode,w,s
endif

common euvflux5, sunlow, sunhigh

if n_elements(sunlow) le 1 then begin
  print, 'Making CHIANTI reference solar spectra...'
  mdir = getenv('henke_model')
  if (strlen(mdir) gt 0) then mdir = mdir + '/'
  restore,mdir + 'ch_ss_sp_dem_all.sav'   ; chwave, chsp, chname, chunits
  ;
  ;  solar min = (QS + CH)/2.  = (chsp[0,*] + chsp[2,*])/2.
  ;
  sunlow=dblarr(2,n_elements(chwave))
  sunlow[0,*] = chwave
  sunlow[1,*] = (chsp[0,*]+chsp[2,*])/2.
  ;
  ;  solar max = solar min + 15% AR  = (chsp[0,*] + chsp[2,*])/2. + 0.15 * chsp[1,*]
  ;
  sunhigh=dblarr(2,n_elements(chwave))
  sunhigh[0,*] = chwave
  sunhigh[1,*] = (chsp[0,*]+chsp[2,*])/2. + 0.15 * chsp[1,*]
  
  ; sunlow = euv81( 90, 90, 2, adjust=1 )		; w = Angstroms
  ; sunhigh = euv81( 200, 200, 2, adjust=1 )	; flux = 10^9 photons/cm^2/s
  
  ;
  ;	convert  CHIANTI radiance   (ph/cm^2/sec/ster/Angstrom) to  1E9 ph/s/cm^2
  ;
  ifactor = 1.6D-19 * 1.D12	; pA/electron
  sunfactor = !pi * ((6.95D8)^2.) / ((1.496D11)^2.)  ; steradians of Sun at Earth (1 AU)
  areafactor = 1.D4		; cm^2 / m^2 factor for irradiance conversion to W/m^2
  hc = 6.26D-34 * 2.998D8
  hcAng = hc / 1D-10		; assuming wavelength is in Angstroms instead of meter

  bandpass = abs(chwave[1]-chwave[0])
  thefactor = 1E-9 * sunfactor * bandpass
  sunlow[1,*] = sunlow[1,*] * thefactor  ; make flux 1E9 ph/s/cm^2
  sunhigh[1,*] = sunhigh[1,*] * thefactor  ; make flux 1E9 ph/s/cm^2

  ; stop, 'Check out sunlow, sunhigh ...'
endif

wv = sunlow(0,*)
;
; current unit is nA  (* 1.6E-19 for e- * 1.E9 for flux * 1.E9 for nA)
;
sslow = interpol( s, w, sunlow(0,*) ) > 0.0
clow = sunlow(1,*) * sslow * 1.602E-1

sshigh = interpol( s, w, sunhigh(0,*) ) > 0.0
chigh = sunhigh(1,*) * sshigh * 1.602E-1

sunavg = sunlow
sunavg[1,*] = (sunlow[1,*]+interpol(sunhigh[1,*],sunhigh[0,*],sunlow[0,*]))/2.

cavg = sunavg[1,*] * sslow * 1.602E-1

wupper = max(w)
if wupper gt 2000 then wupper = 2000
gd = where( sunlow(0,*) lt wupper )

!ytitle = 'Current (nA)'
!xtitle = 'Wavelength (Angstrom)'

!grid = 0

cc = rainbow(7)

wvhigh = sunhigh(0,*)
wvlow = sunlow(0,*)
wvavg = sunavg[0,*]

if keyword_set(nolabel) then begin
	wvhigh = wvhigh/10.
	wvlow = wvlow/10.
	!xtitle = 'Wavelength (nm)'
;	set_xy,0,100,0,0
    xrange2 = [0,140]
	nolabel = 1
endif else begin
	nolabel = 0
;	set_xy,0,1250,0,0
	xrange2 = [0,1400]
endelse

if keyword_set(shortwave) then begin
	xrange2 = [0,100]
endif else if keyword_set(xrange) then xrange2=xrange

setplot
plot, wvhigh, chigh, xrange=xrange2, xs=1

if (nolabel eq 0) then begin

; stop, 'Check out !p.multi for setting character sizes...'
; csize = 1.0 - !p.multi[2] * 0.1
; if csize lt 0.25 then csize = 0.5
csize = 1.5

c2 = cc[0]		; color for solar max
c3 = cc[5]

oplot, wvlow, clow, color=c2
lowfactor = max(chigh)/max(clow)
if (lowfactor gt 10) then oplot, wvlow, clow*lowfactor, color=c3

cnt = 0
ystep = (!y.crange[1]-!y.crange[0])/12.
ystart = !y.crange[1] - 3*ystep
xstep = (!x.crange[1]-!x.crange[0])/10.
x1 = !x.crange[0] + 4. * xstep
x2 = !x.crange[0] + 6. * xstep
x3 = !x.crange[0] + 7.5 * xstep
xyouts, x1, ystart, 'Wavelength',charsize=csize
xyouts, x2, ystart+ystep, 'Solar',charsize=csize
xyouts, x2, ystart, 'Min %',charsize=csize
xyouts, x3, ystart+ystep, 'Solar',charsize=csize
xyouts, x3, ystart, 'Max %',charsize=csize
hightot = total(chigh(gd))
lowtot = total(clow(gd))

do_bandpass = 1	; set to 1 if want special bandpass on plots

;
;	now estimate best bandpass on 1 nm intervals
;	(or 0.1 nm if /shortwave option is given)
;
limit = 1.
kstep = 10L
if keyword_set(shortwave) then kstep = 1L
print, ' '
print, 'Checking for bandpass in ',strtrim(kstep,2), ' Angstrom intervals...'
print, ' '
w1=-1.
w2=1240.
print, ' '
kmax = long(wupper)
for k=0L,kmax,kstep do begin
  wgd = where( (wv ge k) and (wv lt (k+kstep) ) )
  if wgd(0) ne -1 then begin
    plow = total(clow(wgd)) / lowtot * 100.
    phigh = total(chigh(wgd)) / hightot * 100.
    if (plow gt limit) or (phigh gt limit) then begin
	if (w1 lt 0) then w1 = float(k)
	w2 = float(k+kstep)
    endif else if (w1 ge 0) then begin
	print, 'Bandpass = ', w1, w2
	if do_bandpass ne 0 then begin
	  cnt = cnt + 1
	  xyouts, x1, ystart-cnt*ystep, string(fix(w1),'(I4)')+'-'+ $
			string(fix(w2),'(I4)'),charsize=csize
	  wgd = where( (wv ge w1) and (wv lt w2 ) )
  	  plow = total(clow(wgd)) / lowtot * 100.
    	  phigh = total(chigh(wgd)) / hightot * 100.
	  xyouts, x2, ystart-cnt*ystep, string( fix(plow+0.5), '(I3)'),charsize=csize
	  xyouts, x3, ystart-cnt*ystep, string( fix(phigh+0.5), '(I3)'),charsize=csize
          print, string(fix(w1),'(I4)')+'-'+string(fix(w2),'(I4)'), plow, phigh
	endif
	w1 = -1.
    endif
  endif
endfor
print, ' '

if do_bandpass ne 0 then goto, skipregular

limit = 4.5
kstep = 25

for k=0,1200,kstep do begin
  wgd = where( (wv ge k) and (wv lt (k+kstep) ) )
  if wgd(0) ne -1 then begin
    plow = total(clow(wgd)) / lowtot * 100.
    phigh = total(chigh(wgd)) / hightot * 100.
    if (plow gt limit) or (phigh gt limit) then begin
	cnt = cnt + 1
	xyouts, x1, ystart-cnt*ystep, string(k,'(I4)')+'-'+ $
			string(k+kstep,'(I4)'),charsize=csize
	xyouts, x2, ystart-cnt*ystep, string( fix(plow+0.5), '(I3)'),charsize=csize
	xyouts, x3, ystart-cnt*ystep, string( fix(phigh+0.5), '(I3)'),charsize=csize
    endif
  endif
endfor

skipregular:

cnt = cnt + 2
xyouts, x1-0.04*xstep, ystart-cnt*ystep, 'Total Current',charsize=csize
xyouts, x2, ystart-cnt*ystep, string( lowtot, '(F7.3)'),charsize=csize
xyouts, x3, ystart-cnt*ystep, string( hightot, '(F7.3)') + ' nA',charsize=csize

print, 'Assuming 1 cm^2 area...'
print, 'Current (nA) low solar activity is ', lowtot
print, 'Current (nA) high solar activity is ', hightot
print, ' '

;
;	now calculate mean transmission for given bandpass
;
w1 = 0.0
w2 = 350.0
ans=''
redo:
if (n_params(0) lt 4) then read, 'Enter bandpass for this diode (w1, w2) {Ang} : ', w1, w2
if w2 lt w1 then begin
	temp = w1
	w1 = w2
	w2 = temp
endif

wgd2 = where( (wv ge w1) and (wv le w2) )
e_ph = 1.9861E-6 / wv
; convert Sensitivity back to Filter transmission
; and convert Current back to photons and flux in bottom to right units
tfactor = (3.63 * 1.E-9) / e_ph
;
;	take out e_ph weight factors if don't want energy unit usage
;	do integration of T * E over all wavelengths / 
;		/ integration of E ONLY over bandpass
;
avgFlow = total( clow * tfactor * e_ph ) / $
        total( clow(wgd2) * tfactor(wgd2) * e_ph(wgd2) )
avgFhigh = total( chigh * tfactor * e_ph ) / $
        total( chigh(wgd2) * tfactor(wgd2) * e_ph(wgd2) )
avgFavg = total( cavg * tfactor * e_ph ) / $
        total( cavg(wgd2) * tfactor(wgd2) * e_ph(wgd2) )
        
avgTlow = total( clow(wgd2) * tfactor(wgd2) * e_ph(wgd2) ) / $
	total( sunlow(1,wgd2) * e_ph(wgd2) )
avgThigh = total( chigh(wgd2) * tfactor(wgd2) * e_ph(wgd2) ) / $
	total( sunhigh(1,wgd2) * e_ph(wgd2) )
avgTavg = total( cavg(wgd2) * tfactor(wgd2) * e_ph(wgd2) ) / $
	total( sunavg(1,wgd2) * e_ph(wgd2) )
		
;
;	calculate the SPECIAL factor (f) for case where ignore 0-7 nm region
;
wn07 = where( wv gt 70. )	; for all wavelengths beyond 70 Angstroms
spFlow = total( clow[wn07] * tfactor[wn07] * e_ph[wn07] ) / $
        total( clow(wgd2) * tfactor(wgd2) * e_ph(wgd2) )
spFhigh = total( chigh[wn07] * tfactor[wn07] * e_ph[wn07] ) / $
        total( chigh(wgd2) * tfactor(wgd2) * e_ph(wgd2) ) 
spFavg = total( cavg[wn07] * tfactor[wn07] * e_ph[wn07] ) / $
        total( cavg(wgd2) * tfactor(wgd2) * e_ph(wgd2) )

;
;	assume 10% error if not given
;
if (n_params(0) lt 3) then serr = fltarr(n_elements(w)) + 0.10

serror = interpol( serr, w, wv )
avgErrlow = total( serror(wgd2) * sunlow(1,wgd2) * e_ph(wgd2) ) / $
	total( sunlow(1,wgd2) * e_ph(wgd2) )
avgErrhigh = total( serror(wgd2) * sunhigh(1,wgd2) * e_ph(wgd2) ) / $
	total( sunhigh(1,wgd2) * e_ph(wgd2) )


e_ph2 = 1.986e-8/w
www2 = where( (w ge w1) and (w le w2) )
avgT = mean( s(www2) * 3.63 * 1.602E-12 / e_ph2(www2) )

print, ' '
print, 'Avg. Filter Transmission'
print, '------------------------'
print, 'Wavelength range = ', w1, ' - ', w2
print, 'T for NO solar weighting     = ', avgT
print, 'T at low  solar activity level = ', avgTlow, $
	' +/- ', avgErrlow*100.,' %'
print, 'T at high solar activity level = ', avgThigh, $
	' +/- ', avgErrhigh*100.,' %'
;print, 'Difference of <T>   (%)      = ', $
;	abs(avgThigh-avgTlow)*200./(avgThigh+avgTlow)

print, 'Bandpass "f"    (unitless)   = ', avgFavg
print, 'Error for "f"   (%)          = ', $
        abs(avgFhigh-avgFlow)*100./(avgFhigh+avgFlow)
        
print, 'Bandpass <T>    (unitless)   = ', avgTavg
print, 'Error for <T>   (%)          = ', $
        abs(avgThigh-avgTlow)*100./(avgThigh+avgTlow)
        
print, 'Special "f" (> 7nm) (unitless) = ', spFavg
print, 'Error for Special "f"   (%)    = ', $
        abs(spFhigh-spFlow)*100./(spFhigh+spFlow)
print, ' '
; stop, 'Check clow and chigh...'

if (n_params(0) lt 4) then begin
	read, 'Do new bandpass ? (Y/N) ', ans
	if strupcase(strmid(ans,0,1)) eq 'Y' then goto, redo
endif

endif		; for nolabel

wout = wvhigh	; optional output is Solar Max result
sigout = chigh

if keyword_set(stopit) then stop, 'Check out clow and chigh ...'

return
end
