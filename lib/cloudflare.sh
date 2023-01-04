# Cloudflare
#
# Environment variables
#  - CLOUDFLARE_API_Token

CLOUDFLARE_API_BASE='https://api.cloudflare.com/client/v4/zones'
CLOUDFLARE_AUTH="Authorization: Bearer $CLOUDFLARE_API_Token"
JSON='Content-Type: application/json'

shopt -s expand_aliases
alias cloudflare="curl --fail --retry 30 --retry-delay 10 --retry-all-errors --no-progress-meter -H '$CLOUDFLARE_AUTH'"

cloudflare_dns_update () {
	local domain=$1 type=$2 name=$3 content=$4 zone_id
	name=$([[ $name == '@' ]] && echo "$domain" || echo "$name.$domain")
	zone_id=$(cloudflare_get_zone_id) &&
	cloudflare_dns_delete &&
	cloudflare_dns_add || { 
		echo "cloudflare DNS update failed: $domain $type $name $content" && return 1
	}
}

cloudflare_get_zone_id () {
	cloudflare -G -d "name=$domain" "$CLOUDFLARE_API_BASE" | jq -er '.result[0].id'
}

# cloudflare_dns_get_record () {
# 	local domain=$1 type=$2 name=$3 content=$4 zone_id
# 	name=$([[ $name == '@' ]] && echo "$domain" || echo "$name.$domain")

# 	zone_id=$(cloudflare_get_zone_id) 

# 	local base_url="$CLOUDFLARE_API_BASE/$zone_id/dns_records"
# 	cloudflare -G -d "name=$name" -d "type=$type" $base_url  | jq -r '.result[].id'
# }

cloudflare_dns_delete () {
	local base_url="$CLOUDFLARE_API_BASE/$zone_id/dns_records"
	cloudflare -G -d "name=$name" -d "type=$type" $base_url | jq -r '.result[].id' | while read record_id
	do
		cloudflare -X DELETE "$base_url/$record_id" >/dev/null
	done
}

cloudflare_dns_add () {
	local data
	data=$(jq -n --arg type $type --arg name $name --arg content "$content" '{"type":$type,"name":$name,"content":$content,"ttl":60,"proxied":false}')
	[[ $type == "MX" ]] && data=$(jq '. + {"priority": 0}' <<<$data)
	# [[ $type =~ ^("MX"|"SRV")$ ]] && data=$(jq -r '. + {"priority": 0}' <<<$data)
	cloudflare -H "$JSON" -d "$data" "$CLOUDFLARE_API_BASE/$zone_id/dns_records" 
}
