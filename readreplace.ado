*! v1 by Ryan Knight 12jan2011
pr readreplace, rclass
	vers 10.1

	syntax using, id(varname) [DIsplay]

	preserve

	* Import the replacements file.
	loc cmd insheet `using', clear
	cap `cmd'
	if _rc {
		loc rc = _rc
		* Display the error message.
		cap noi `cmd'
		ex `rc'
	}

	unab rest : _all
	gettoken first		rest : rest
	gettoken variable	rest : rest
	gettoken value : rest

	if "`first'" != "`id'" | c(k) != 3 {
		di _newline as err "Error: Using file has improper format"
		di as txt "The using file must have the format: " as res "`id',varname,correct_value"
		ex 198
	}

	if "`display'" != "" {
		di as txt "note: option {opt display} is deprecated " ///
			"and will be ignored."
	}

	keep `id' `variable' `value'
	qui tostring `value', replace format(%24.0g)
	conf str var `value'
	sort `variable', stable
	mata: readreplace("id", "variable", "value", "varlist", "N", "changes")
	* Return stored results.
	ret sca N = `N'
	ret loc varlist `varlist'
	if `return(N)' ///
		ret mat changes = `changes'

	di as txt _n "Total changes made: " as res `return(N)'

	restore, not

	/*
	* Loop through lines in the file, making replacements as necessary
	local changes = 0
	file read `myfile' line
	while r(eof)==0 {
		gettoken idval 0: line, parse(",")
		gettoken c1 0: 0, parse(",")
		gettoken q 0: 0, parse(",")
		if `"`q'"' == "," {
			di as err `"Question missing in line `line' "'
			exit 198
		}
		gettoken c2 0: 0, parse(",")
		local qval `0'

		* Delete double quotes that result if you use commas within quotes in a csv file
		local qval: subinstr local qval `""""' `"""', all

		* check that q is a variable
		capture confirm variable `q'
		if _rc {
			di _newline as err "Error!" _newline as res "`q'" as txt " is not a variable name"
			di as txt "The using file must have the format: " as res "`id',varname,correct_value"
			file close `myfile'
			exit 198
		}

		* check that the observation exists
		qui count if `id' == `quote'`idval'`quote'
		if `r(N)' == 0 {
			di _newline as err "Observation " as res `"`idval'"' as err " not found"
			file close `myfile'
			exit 198
		}

		* Check var type
		capture confirm numeric variable `q'
		if _rc {
			local vquote `"""'
		}
		else {
			local vquote
			if `"`qval'"' == `""' {
				local qval .
			}
		}

		* Make replacement
		qui count if `q'!=`vquote'`qval'`vquote' & `id'==`quote'`idval'`quote'
		local changes = `changes' + `r(N)'
		if `r(N)' > 0 {
			replace `q'=`vquote'`qval'`vquote' if `id'==`quote'`idval'`quote'
		}
		file read `myfile' line
	}
	*/
end


/* -------------------------------------------------------------------------- */
					/* type definitions, etc.	*/

* Convert real x to string using -strofreal(x, `RealFormat')-.
loc RealFormat	""%24.0g""

loc RS	real scalar
loc RR	real rowvector
loc RC	real colvector
loc RM	real matrix
loc SS	string scalar
loc SR	string rowvector
loc SC	string colvector
loc SM	string matrix
loc TS	transmorphic scalar
loc TR	transmorphic rowvector
loc TC	transmorphic colvector
loc TM	transmorphic matrix

loc boolean		`RS'
loc True		1
loc False		0

* A local macro name
loc lclname		`SS'

mata:

					/* type definitions, etc.	*/
/* -------------------------------------------------------------------------- */


/* -------------------------------------------------------------------------- */
					/* interface with Stata		*/

// Returns `True' if any of vars are strL and `False' if not.
`boolean' st_anystrL(`TR' vars)
{
	`RS' n, i
	`boolean' any

	any = `False'
	i = 0
	n = length(vars)
	while (++i <= n & !any)
		any = st_vartype(vars[i]) == "strL"

	return(any)
}

// With parallel syntax to -st_sview()-, for observations i and variables j,
// if any of j are strL, makes V a copy of the specified dataset subset;
// if none are, makes V a view.
void st_sviewL(`TM' V, `RM' i, `TR' j)
{
	if (st_anystrL(j))
		V = st_sdata(i, j)
	else {
		pragma unset V
		st_sview(V, i, j)
	}
}

// Returns the list of numeric types that can store the values of X.
// The list is ordered by decreasing precision (for noninteger X) and
// increasing size, meaning that the first element is often the optimal type.
`SR' numeric_types(`RM' X)
{
	`RS' min, max, n
	`SR' types

	n = length(X)
	if (!all(X :== floor(X)) & n)
		types = "double", "float"
	else {
		min = min(X)
		max = max(X)

		pragma unset types
		if (min >= -127 & max <= 100 | !n)
			types = types, "byte"
		if (min >= -32767 & max <= 32740 | !n)
			types = types, "int"
		if (min >= -9999999 & max <= 9999999 | !n)
			types = types, "float"
		if (min >= -2147483647 & max <= 2147483620 | !n)
			types = types, "long"
		types = types, "double"
	}

	return(types)
}

// Promotes the storage type of variable var so that
// it can store the values of X.
void st_promote_type(`SS' var, `TM' X)
{
	`RS' maxlen
	`SS' type_old, type_new, strpound
	`SR' numtypes

	type_new = type_old = st_vartype(var)
	if (st_isnumvar(var)) {
		// Never recast floats to doubles.
		numtypes = numeric_types(X)
		if (!anyof(numtypes, type_old))
			type_new = numtypes[1]
	}
	else {
		if (type_old != "strL") {
			maxlen = max(strlen(X))
			if (maxlen == .)
				maxlen = 0
			if (strtoreal(subinstr(type_old, "str", "", 1)) < maxlen) {
				strpound = sprintf("str%f",
					min((max((maxlen, 1)), c("maxstrvarlen"))))
				if (c("stata_version") < 13)
					type_new = strpound
				else
					type_new = maxlen <= c("maxstrvarlen") ? strpound : "strL"
			}
		}
	}

	if (type_new != type_old) {
		printf("{txt}%s was {res:%s} now {res:%s}\n", var, type_old, type_new)
		stata(sprintf("recast %s %s", type_new, var))
	}
}

`SR' st_sortlist()
{
	stata("qui d, varl")
	return(tokens(st_global("r(sortlist)")))
}

					/* interface with Stata		*/
/* -------------------------------------------------------------------------- */


/* -------------------------------------------------------------------------- */
					/* make replacements	*/

void split_rowvector(`TR' v, `TR' v_if_true, `TR' v_if_false,
	pointer(`boolean' function) splitter, |`RR' splitres)
{
	`RS' n, i
	`SS' eltype

	eltype = eltype(v)
	if (eltype == "real")
		v_if_true = v_if_false = J(1, 0, .)
	else if (eltype == "string")
		v_if_true = v_if_false = J(1, 0, "")
	else
		_error("invalid eltype")

	n = length(v)
	splitres = J(1, n, `False')
	for (i = 1; i <= n; i++) {
		if ((*splitter)(v[i])) {
			v_if_true = v_if_true, v[i]
			splitres[i] = `True'
		}
		else
			v_if_false = v_if_false, v[i]
	}
}

`boolean' st_isnumvar_cp(`TS' var)
	return(st_isnumvar(var))

void readreplace(
	/* variable names */
	`lclname' _id, `lclname' _variable, `lclname' _value,
	/* output */
	`lclname' _varlist, `lclname' _changes_N, `lclname' _changes_mat)
{
	// "repl" for "replacement"
	`RS' id_num_k, id_str_k, repl_N, repl_k, i, j
	`RR' changes
	`RC' value_num, obsnum, touse, touseobs
	// "r" suffix for "replacements file"; "m" suffix for "master."
	`RM' id_num_r, id_num_m
	`SS' prev, changes_name
	`SR' sortlist, id_num_names, id_str_names, repl_names
	`SC' variable, value
	`SM' id_str_r, id_str_m
	`TS' val
	`TC' repl_view
	`boolean' isnum, isstrL

	// Save the replacements file.

	// Check that the dataset is sorted by the variable name variable.
	sortlist = st_sortlist()
	assert(length(sortlist))
	assert(sortlist[1] == st_local(_variable))

	// ID variables
	pragma unset id_num_names
	pragma unset id_str_names
	split_rowvector(tokens(st_local(_id)), id_num_names, id_str_names,
		&st_isnumvar_cp())
	if (id_num_k = length(id_num_names))
		id_num_r = st_data( ., id_num_names)
	if (id_str_k = length(id_str_names))
		id_str_r = st_sdata(., id_str_names)
	assert(id_num_k | id_str_k)

	// Variable name and new value variables
	variable = st_sdata(., st_local(_variable))
	value    = st_sdata(., st_local(_value))
	value_num = strtoreal(value)

	repl_N = st_nobs()

	stata("restore, preserve")

	if (!repl_N) {
		st_local(_varlist, "")
		st_local(_changes_N, "0")
		st_local(_changes_mat, "")
		return
	}

	// Create views onto the ID variables of the master dataset.
	if (id_num_k) {
		pragma unset id_num_m
		st_view(  id_num_m, ., id_num_names)
	}
	if (id_str_k) {
		pragma unset id_str_m
		st_sviewL(id_str_m, ., id_str_names)
	}

	// Promote variable types.
	repl_names = uniqrows(variable)'
	repl_k = length(repl_names)
	for (i = 1; i <= repl_k; i++) {
		st_promote_type(repl_names[i],
			select((st_isnumvar(repl_names[i]) ? value_num : value),
			variable :== repl_names[i]))
	}

	// Make the replacements.
	changes = J(1, repl_k, 0)
	prev = ""
	j = 0
	obsnum = 1::st_nobs()
	for (i = 1; i <= repl_N; i++) {
		// Change in variable name
		if (variable[i] != prev) {
			prev = variable[i]
			j++
			pragma unset repl_view
			if (isnum = st_isnumvar(variable[i]))
				st_view(  repl_view, ., variable[i])
			else
				st_sviewL(repl_view, ., variable[i])
			isstrL = st_vartype(variable[i]) == "strL"
		}

		// Select observations by ID.
		touse = J(st_nobs(), 1, `True')
		if (id_num_k)
			touse = touse :& rowsum(id_num_m :== id_num_r[i,]) :== id_num_k
		if (id_str_k)
			touse = touse :& rowsum(id_str_m :== id_str_r[i,]) :== id_str_k
		touseobs = select(obsnum, touse)

		// Changes
		val = isnum ? value_num[i] : value[i]
		changes[j] = changes[j] + sum(repl_view[touseobs] :!= val)
		if (isstrL)
			st_sstore(touseobs, variable[i], J(length(touseobs), 1, val))
		else
			repl_view[touseobs] = J(length(touseobs), 1, val)
	}

	// Return results to Stata.
	st_local(_varlist, invtokens(repl_names))
	st_local(_changes_N, strofreal(sum(changes), `RealFormat'))
	changes_name = st_tempname()
	st_matrix(changes_name, changes)
	st_matrixrowstripe(changes_name, ("", "changes"))
	st_matrixcolstripe(changes_name, (J(repl_k, 1, ""), repl_names'))
	st_local(_changes_mat, changes_name)
}

					/* make replacements	*/
/* -------------------------------------------------------------------------- */

end
