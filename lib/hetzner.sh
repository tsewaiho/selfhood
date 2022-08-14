# Hetzner
#
# Environment variables
#  - HCLOUD_API_TOKEN
#
# Hetnzer have 4 locations
# The germany location has the best average ping. The Finland has the slowest Internet speed according to speedtest.net
#   and fast.com, but the usabilly is not that poor. US has the fastest Internet speed but the actual user experience
#   is not that good because of worst ping. The best advantage of US is the US ip address, good for Youtube and most
#   search engine.
# fsn1	Falkenstein		DE	182ms
# nbg1	Nuremberg		DE	182ms
# hel1	Helsinki		FI	205ms
# ash	Ashburn			US	217ms


HCLOUD_API_BASE='https://api.hetzner.cloud/v1'
HCLOUD_AUTH="Authorization: Bearer $HCLOUD_API_TOKEN"
JSON='Content-Type: application/json'

shopt -s expand_aliases
alias hcloud="curl --fail --retry 30 --retry-delay 10 --no-progress-meter -H '$HCLOUD_AUTH'"

server_setup () {
	local name=$1 domain=$2 user_data=$3 server_id
	local -n ip_address_ref=$4

	hetzner_delete_ssh_key &&
	hetzner_create_ssh_key &&
	hetzner_delete_server &&
	hetzner_create_server &&
	hetzner_change_dns_ptr &&
	echo "Gateway's admin password is null. This VPS provider do not set the root password."
}

# The SSH key and key name must be unique because if I create a duplicate one, the server will returns
#   "SSH key name is already used" or "SSH key with the same fingerprint already exists".
hetzner_delete_ssh_key () {
	local existing_ssh_key_id
	existing_ssh_key_id=$(hcloud -G -d "name=$name" "$HCLOUD_API_BASE/ssh_keys" | jq -r '.ssh_keys[0].id') && {
		[ $existing_ssh_key_id = 'null' ] ||
		hcloud -X DELETE "$HCLOUD_API_BASE/ssh_keys/$existing_ssh_key_id";
	}
}

hetzner_create_ssh_key () {
	local data public_key
	public_key=$(<$HOME/.ssh/id_ed25519.pub) &&
	data=$(jq -n --arg name "$name" --arg public_key "$public_key" '{"name":$name,"public_key":$public_key}') &&
	hcloud -H "$JSON" -d "$data" "$HCLOUD_API_BASE/ssh_keys"
}

# The server name must be unique because if I create a duplicate one, the server will return "server name is already used".
hetzner_delete_server () {
	local existing_server_id
	existing_server_id=$(hcloud -G -d "name=$name" "$HCLOUD_API_BASE/servers" | jq -r '.servers[0].id') && {
		[ $existing_server_id = 'null' ] ||
		hcloud -X DELETE "$HCLOUD_API_BASE/servers/$existing_server_id";
	}
}

hetzner_create_server () {
	local data server
	data=$(jq -n --arg name "$name" --arg ssh_key "$name" --arg user_data "$user_data" '{"image":"debian-11","location":"fsn1","name":$name,"server_type":"cpx11","ssh_keys":[$ssh_key],"user_data":$user_data}') &&
	server=$(hcloud -H "$JSON" -d "$data" "$HCLOUD_API_BASE/servers") &&
	ip_address_ref=$(jq -er '.server.public_net.ipv4.ip' <<<$server) &&
	server_id=$(jq -er '.server.id' <<<$server) || {
		echo 'hetzner_create_server encounter error.' && return 1;
	}
}

hetzner_change_dns_ptr () {
	local data
	data=$(jq -n --arg dns_ptr "$domain" --arg ip "$ip_address_ref" '{"dns_ptr": $dns_ptr,"ip": $ip}') &&
	hcloud -H "$JSON" -d "$data" "$HCLOUD_API_BASE/servers/$server_id/actions/change_dns_ptr"
}
