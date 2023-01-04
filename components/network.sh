tee /etc/systemd/system/known_devices_table.service <<-EOF >/dev/null
[Unit]
Description=Manual routing table with high priority for known device
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=ip rule add from all lookup $KNOWN_DEVICES_TABLE priority $KNOWN_DEVICES_PRIORITY

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now known_devices_table
