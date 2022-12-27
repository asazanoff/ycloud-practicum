#Bash file for lesson in Yandex Practicum (ycloud)
#Uses in yc command for cloud-init module

#!/bin/bash
apt-get update
apt-get install -y nginx
service nginx start
sed -i -- "s/nginx/Yandex Cloud - ${HOSTNAME}/" /var/www/html/index.nginx-debian.html
EOF
