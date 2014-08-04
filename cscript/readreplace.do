* -readreplace- cscript

* -version- intentionally omitted for -cscript-.

* 1 to execute profile.do after completion; 0 not to.
local profile 1


/* -------------------------------------------------------------------------- */
					/* initialize			*/

* Check the parameters.
assert inlist(`profile', 0, 1)

* Set the working directory to the readreplace directory.
c readreplace
cd cscript

cap log close readreplace
log using readreplace, name(readreplace) s replace
di "`c(username)'"
di "`:environment computername'"

clear
if c(stata_version) >= 11 ///
	clear matrix
clear mata
set varabbrev off
set type float
vers 10.1: set seed 529948906
set more off

cd ..
adopath ++ `"`c(pwd)'"'
adopath ++ `"`c(pwd)'/cscript/ado"'
cd cscript

timer clear 1
timer on 1

* Preserve select globals.
loc FASTCDPATH : copy glo FASTCDPATH

cscript readreplace adofile readreplace

* Check that Mata issues no warning messages about the source code.
if c(stata_version) >= 13 {
	matawarn readreplace.ado
	assert !r(warn)
	cscript
}

* Restore globals.
glo FASTCDPATH : copy loc FASTCDPATH

cd tests


/* -------------------------------------------------------------------------- */
					/* basic				*/

* Test 1
cd 1
u firstEntry, clear
readreplace using correctedValues.csv, id(uniqueid)
cd ..


/* -------------------------------------------------------------------------- */
					/* user mistakes		*/

// ...


/* -------------------------------------------------------------------------- */
					/* finish up			*/

cd ..

timer off 1
timer list 1

if `profile' {
	cap conf f C:\ado\profile.do
	if !_rc ///
		run C:\ado\profile
}

timer list 1

log close readreplace
