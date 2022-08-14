# Cloudflare
#
# Environment variables
#  - CLOUDFLARE_API_Token

CLOUDFLARE_API_BASE='https://api.cloudflare.com/client/v4/zones'
CLOUDFLARE_AUTH="Authorization: Bearer $CLOUDFLARE_API_Token"
JSON='Content-Type: application/json'

shopt -s expand_aliases
alias cloudflare="curl --fail --retry 30 --retry-delay 10 --no-progress-meter -H '$CLOUDFLARE_AUTH'"

cloudflare_dns_update () {
	local name=$1 domain=$2 ip_address=$3 zone_id
	zone_id=$(cloudflare_get_zone_id) &&
	cloudflare_dns_delete &&
	cloudflare_dns_add
}

cloudflare_get_zone_id () {
	cloudflare -G -d "name=$domain" "$CLOUDFLARE_API_BASE" | jq -er '.result[0].id'
}

cloudflare_dns_delete () {
	local base_url="$CLOUDFLARE_API_BASE/$zone_id/dns_records"
  cloudflare $base_url | jq -r --arg name "$name.$domain" '.result[] | select(.name==$name and .type=="A").id' | while read record_id
	do
		cloudflare -X DELETE "$base_url/$record_id" >/dev/null
	done
}

cloudflare_dns_add () {
	local data
	data=$(jq -n --arg name $name --arg ip_address $ip_address '{"type":"A","name":$name,"content":$ip_address,"ttl":60,"proxied":false}')
	cloudflare -H "$JSON" -d "$data" "$CLOUDFLARE_API_BASE/$zone_id/dns_records" >/dev/null
}
