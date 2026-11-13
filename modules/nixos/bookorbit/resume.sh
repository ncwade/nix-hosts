# Called normally and by systemd even if the backup is interrupted.
status=0
for service in tsidp podman-bookorbit bookorbit-tailnet bookorbit-tailnet-serve; do
  marker=/run/bookorbit-backup/resume-$service
  if [ -e "$marker" ]; then
    if systemctl start "$service.service"; then
      rm -f "$marker"
    else
      status=1
    fi
  fi
done
exit "$status"
