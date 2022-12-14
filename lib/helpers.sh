runasroot () {
	if [ `id -u` -ne 0 ]; then
		echo "Please run as root."
		exit 1
	fi
}

# minify remove comments and empty lines.
minify () {
	# Default comment symbol is '#', some config file like php use ';'.
	local filename=$1 comment_symbol=${2:-#}

	# Do not specify any option after '-i', because it will be treat as parameter to the '-i' option.
	#   -i[SUFFIX]
	#       edit files in place (makes backup if SUFFIX supplied)
	sed -ri "/^\s*($comment_symbol|$)/d" $filename
}

base64_hash () {
	local password=$1 salt=${2:-$MASTER_PASSWORD}
	echo -n "$password" | argon2 "$salt" -r | xxd -r -p | base64 -w 0
}

z85_hash () {
	local password=$1 salt=${2:-$MASTER_PASSWORD}
	echo -n "$password" | argon2 "$salt" -r | xxd -r -p | basenc --z85 -w 0
}